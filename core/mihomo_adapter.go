package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"io"
	"maps"
	"net"
	"os"
	"reflect"
	"runtime"
	"slices"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/provider"
	mihomoAtomic "github.com/metacubex/mihomo/common/atomic"
	"github.com/metacubex/mihomo/common/buf"
	N "github.com/metacubex/mihomo/common/net"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	rp "github.com/metacubex/mihomo/rules/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type providerVersionState struct {
	ptr     uintptr
	version uint32
}

var (
	tunnelCacheMu           sync.RWMutex
	tunnelSnapshotActive    bool
	tunnelProxiesSnapshot   map[string]constant.Proxy
	tunnelProvidersSnapshot map[string]cp.ProxyProvider
	tunnelRuleProvidersSnap map[string]cp.RuleProvider
	allProxiesCached        map[string]constant.Proxy
	cachedBasePtr           uintptr
	cachedBaseLen           int
	cachedProvPtr           uintptr
	cachedProvLen           int
	cachedProvVersionStates map[string]providerVersionState
)

func pointerOf(value any) uintptr {
	if value == nil {
		return 0
	}
	rv := reflect.ValueOf(value)
	switch rv.Kind() {
	case reflect.Ptr, reflect.Map, reflect.Slice, reflect.Chan, reflect.Func, reflect.UnsafePointer:
		return rv.Pointer()
	default:
		return 0
	}
}

func updateTunnelProxies(proxies map[string]constant.Proxy, providers map[string]cp.ProxyProvider) {
	tunnelCacheMu.Lock()
	defer tunnelCacheMu.Unlock()
	tunnel.UpdateProxies(proxies, providers)
	tunnelSnapshotActive = true
	tunnelProxiesSnapshot = maps.Clone(proxies)
	tunnelProvidersSnapshot = maps.Clone(providers)
	resetAllProxiesCacheLocked()
}

func updateTunnelRules(
	rules []constant.Rule,
	subRules map[string][]constant.Rule,
	ruleProviders map[string]cp.RuleProvider,
) {
	tunnelCacheMu.Lock()
	defer tunnelCacheMu.Unlock()
	tunnel.UpdateRules(rules, subRules, ruleProviders)
	tunnelSnapshotActive = true
	tunnelRuleProvidersSnap = maps.Clone(ruleProviders)
}

func syncTunnelSnapshotsFromTunnel(keepSnapshot bool) {
	tunnelCacheMu.Lock()
	defer tunnelCacheMu.Unlock()
	if keepSnapshot {
		tunnelSnapshotActive = true
		tunnelProxiesSnapshot = maps.Clone(tunnel.Proxies())
		tunnelProvidersSnapshot = maps.Clone(tunnel.Providers())
		tunnelRuleProvidersSnap = maps.Clone(tunnel.RuleProviders())
	} else {
		tunnelSnapshotActive = false
		tunnelProxiesSnapshot = nil
		tunnelProvidersSnapshot = nil
		tunnelRuleProvidersSnap = nil
	}
	resetAllProxiesCacheLocked()
}

func clearTunnelSnapshots() {
	syncTunnelSnapshotsFromTunnel(false)
}

func resetAllProxiesCacheLocked() {
	allProxiesCached = nil
	cachedBasePtr = 0
	cachedBaseLen = 0
	cachedProvPtr = 0
	cachedProvLen = 0
	cachedProvVersionStates = nil
}

func invalidateAllProxies() {
	tunnelCacheMu.Lock()
	defer tunnelCacheMu.Unlock()
	resetAllProxiesCacheLocked()
}

func providersSnapshot() map[string]cp.ProxyProvider {
	tunnelCacheMu.RLock()
	defer tunnelCacheMu.RUnlock()
	if tunnelSnapshotActive {
		return maps.Clone(tunnelProvidersSnapshot)
	}
	return tunnel.Providers()
}

func ruleProvidersSnapshot() map[string]cp.RuleProvider {
	tunnelCacheMu.RLock()
	defer tunnelCacheMu.RUnlock()
	if tunnelSnapshotActive {
		return maps.Clone(tunnelRuleProvidersSnap)
	}
	return tunnel.RuleProviders()
}

func baseProxiesLocked() map[string]constant.Proxy {
	if tunnelSnapshotActive {
		return tunnelProxiesSnapshot
	}
	return tunnel.Proxies()
}

func proxyProvidersLocked() map[string]cp.ProxyProvider {
	if tunnelSnapshotActive {
		return tunnelProvidersSnapshot
	}
	return tunnel.Providers()
}

func allProxiesCacheValidLocked(
	base map[string]constant.Proxy,
	providers map[string]cp.ProxyProvider,
) bool {
	if allProxiesCached == nil {
		return false
	}
	if pointerOf(base) != cachedBasePtr || len(base) != cachedBaseLen {
		return false
	}
	if pointerOf(providers) != cachedProvPtr || len(providers) != cachedProvLen {
		return false
	}
	if len(providers) != len(cachedProvVersionStates) {
		return false
	}
	for name, pd := range providers {
		prev, ok := cachedProvVersionStates[name]
		if !ok {
			return false
		}
		if pd == nil {
			if prev.ptr != 0 {
				return false
			}
			continue
		}
		if pointerOf(pd) != prev.ptr || pd.Version() != prev.version {
			return false
		}
	}
	return true
}

func allProxies() map[string]constant.Proxy {
	tunnelCacheMu.RLock()
	base := baseProxiesLocked()
	providers := proxyProvidersLocked()
	if allProxiesCacheValidLocked(base, providers) {
		cached := allProxiesCached
		tunnelCacheMu.RUnlock()
		return cached
	}
	tunnelCacheMu.RUnlock()

	tunnelCacheMu.Lock()
	defer tunnelCacheMu.Unlock()
	base = baseProxiesLocked()
	providers = proxyProvidersLocked()
	if allProxiesCacheValidLocked(base, providers) {
		return allProxiesCached
	}

	merged := make(map[string]constant.Proxy, len(base))
	for name, proxy := range base {
		merged[name] = proxy
	}

	providerNames := make([]string, 0, len(providers))
	for name := range providers {
		providerNames = append(providerNames, name)
	}
	sort.Strings(providerNames)

	versionStates := make(map[string]providerVersionState, len(providers))
	for _, name := range providerNames {
		pd := providers[name]
		if pd == nil {
			versionStates[name] = providerVersionState{}
			continue
		}
		versionStates[name] = providerVersionState{
			ptr:     pointerOf(pd),
			version: pd.Version(),
		}
		for _, proxy := range pd.Proxies() {
			merged[proxy.Name()] = proxy
		}
	}

	allProxiesCached = merged
	cachedBasePtr = pointerOf(base)
	cachedBaseLen = len(base)
	cachedProvPtr = pointerOf(providers)
	cachedProvLen = len(providers)
	cachedProvVersionStates = versionStates
	return merged
}

func proxyNameList() []string {
	providers := providersSnapshot()
	if def, ok := providers[provider.ReservedName]; ok && def != nil {
		proxies := def.Proxies()
		names := make([]string, 0, len(proxies))
		for _, proxy := range proxies {
			names = append(names, proxy.Name())
		}
		return names
	}
	proxies := allProxies()
	names := make([]string, 0, len(proxies))
	for name := range proxies {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

type proxyTrafficTracker struct {
	startOnce     sync.Once
	uploadTemp    atomic.Int64
	downloadTemp  atomic.Int64
	uploadBlip    atomic.Int64
	downloadBlip  atomic.Int64
	uploadTotal   atomic.Int64
	downloadTotal atomic.Int64
}

var proxyTraffic = &proxyTrafficTracker{}

func (t *proxyTrafficTracker) ensureRunning() {
	t.startOnce.Do(func() {
		go func() {
			ticker := time.NewTicker(time.Second)
			defer ticker.Stop()
			for range ticker.C {
				t.uploadBlip.Store(t.uploadTemp.Swap(0))
				t.downloadBlip.Store(t.downloadTemp.Swap(0))
			}
		}()
	})
}

func (t *proxyTrafficTracker) recordUpload(size int64) {
	if size <= 0 {
		return
	}
	t.ensureRunning()
	t.uploadTemp.Add(size)
	t.uploadTotal.Add(size)
}

func (t *proxyTrafficTracker) recordDownload(size int64) {
	if size <= 0 {
		return
	}
	t.ensureRunning()
	t.downloadTemp.Add(size)
	t.downloadTotal.Add(size)
}

func (t *proxyTrafficTracker) Now() (int64, int64) {
	t.ensureRunning()
	return t.uploadBlip.Load(), t.downloadBlip.Load()
}

func (t *proxyTrafficTracker) Total() (int64, int64) {
	return t.uploadTotal.Load(), t.downloadTotal.Load()
}

func (t *proxyTrafficTracker) Reset() {
	t.uploadTemp.Store(0)
	t.downloadTemp.Store(0)
	t.uploadBlip.Store(0)
	t.downloadBlip.Store(0)
	t.uploadTotal.Store(0)
	t.downloadTotal.Store(0)
}

func isDirectOrBuiltinType(adapterType constant.AdapterType) bool {
	switch adapterType {
	case constant.Direct, constant.Reject, constant.RejectDrop,
		constant.Compatible, constant.Pass, constant.PassRule, constant.Dns:
		return true
	default:
		return false
	}
}

func isProxyChain(chains constant.Chain) bool {
	leaf := chains.Last()
	if leaf == "" {
		return false
	}
	switch leaf {
	case "DIRECT", "REJECT", "REJECT-DROP", "COMPATIBLE", "PASS", "PASS-RULE":
		return false
	}
	if proxy := allProxies()[leaf]; proxy != nil {
		return !isDirectOrBuiltinType(proxy.Type())
	}
	return true
}

// wrappedDialKey prevents nested dialer-proxy hops from double-counting traffic
// or duplicating request notifications.
type wrappedDialKey struct{}

type pendingRequest struct {
	id       uint64
	meta     *constant.Metadata
	chains   constant.Chain
	pdChains constant.Chain
	started  time.Time
	upload   atomic.Int64
	download atomic.Int64
	matched  atomic.Bool
	closed   atomic.Bool
}

type requestMonitorState struct {
	mu      sync.Mutex
	nextID  uint64
	seen    map[string]struct{}
	pending []*pendingRequest
	notify  chan struct{}
}

var requestMonitor = &requestMonitorState{
	seen:   make(map[string]struct{}),
	notify: make(chan struct{}, 1),
}

func (m *requestMonitorState) reset() {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.seen = make(map[string]struct{})
	m.pending = nil
}

func (m *requestMonitorState) registerDial(
	meta *constant.Metadata,
	chains constant.Chain,
	pdChains constant.Chain,
) *pendingRequest {
	if meta == nil {
		return nil
	}
	m.mu.Lock()
	m.nextID++
	req := &pendingRequest{
		id:       m.nextID,
		meta:     meta.Clone(),
		chains:   slices.Clone(chains),
		pdChains: slices.Clone(pdChains),
		started:  time.Now(),
	}
	if len(m.pending) > 512 {
		m.pending = m.pending[len(m.pending)-256:]
	}
	m.pending = append(m.pending, req)
	m.mu.Unlock()

	select {
	case m.notify <- struct{}{}:
	default:
	}
	return req
}

func (m *requestMonitorState) finishDial(req *pendingRequest) {
	if req == nil {
		return
	}
	req.closed.Store(true)
	m.scanSnapshot()
	if !req.matched.Swap(true) {
		m.removePending(req.id)
		emitRequestInfo(&statistic.TrackerInfo{
			UUID:          utils.NewUUIDV4(),
			Metadata:      req.meta,
			UploadTotal:   mihomoAtomic.NewInt64(req.upload.Load()),
			DownloadTotal: mihomoAtomic.NewInt64(req.download.Load()),
			Start:         req.started,
			Chain:         req.chains,
			ProviderChain: req.pdChains,
		})
	}
}

func (m *requestMonitorState) removePending(id uint64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.pending = slices.DeleteFunc(m.pending, func(item *pendingRequest) bool {
		return item.id == id
	})
}

func sameTrackerSignature(req *pendingRequest, info *statistic.TrackerInfo) bool {
	if req.meta == nil || info.Metadata == nil {
		return false
	}
	if req.meta.NetWork != info.Metadata.NetWork ||
		req.meta.SrcPort != info.Metadata.SrcPort ||
		req.meta.DstPort != info.Metadata.DstPort ||
		req.meta.SrcIP != info.Metadata.SrcIP {
		return false
	}
	return slices.Equal(req.chains, info.Chain)
}

func (m *requestMonitorState) scanSnapshot() {
	snapshot := statistic.DefaultManager.Snapshot()
	if snapshot == nil {
		return
	}
	activeIDs := make(map[string]struct{}, len(snapshot.Connections))
	var fresh []*statistic.TrackerInfo

	m.mu.Lock()
	for _, info := range snapshot.Connections {
		if info == nil {
			continue
		}
		id := info.UUID.String()
		activeIDs[id] = struct{}{}
		if _, exists := m.seen[id]; exists {
			continue
		}
		m.seen[id] = struct{}{}
		for _, req := range m.pending {
			if !req.matched.Load() && sameTrackerSignature(req, info) {
				req.matched.Store(true)
				break
			}
		}
		fresh = append(fresh, info)
	}
	for id := range m.seen {
		if _, active := activeIDs[id]; !active {
			delete(m.seen, id)
		}
	}
	m.pending = slices.DeleteFunc(m.pending, func(item *pendingRequest) bool {
		return item.matched.Load() || (item.closed.Load() && time.Since(item.started) > 5*time.Second)
	})
	m.mu.Unlock()

	for _, info := range fresh {
		emitRequestInfo(info)
	}
}

func emitRequestInfo(info *statistic.TrackerInfo) {
	if info == nil {
		return
	}
	sendMessage(Message{
		Type: RequestMessage,
		Data: info,
	})
}

type trackedConn struct {
	constant.Conn
	isProxy bool
	req     *pendingRequest
}

func newTrackedConn(c constant.Conn, isProxy bool, meta *constant.Metadata) constant.Conn {
	return &trackedConn{
		Conn:    c,
		isProxy: isProxy,
		req:     requestMonitor.registerDial(meta, c.Chains(), c.ProviderChains()),
	}
}

func (c *trackedConn) recordDownload(size int64) {
	if size <= 0 {
		return
	}
	if c.isProxy {
		proxyTraffic.recordDownload(size)
	}
	if c.req != nil {
		c.req.download.Add(size)
	}
}

func (c *trackedConn) recordUpload(size int64) {
	if size <= 0 {
		return
	}
	if c.isProxy {
		proxyTraffic.recordUpload(size)
	}
	if c.req != nil {
		c.req.upload.Add(size)
	}
}

func (c *trackedConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	c.recordDownload(int64(n))
	return n, err
}

func (c *trackedConn) ReadBuffer(buffer *buf.Buffer) error {
	err := c.Conn.ReadBuffer(buffer)
	c.recordDownload(int64(buffer.Len()))
	return err
}

func (c *trackedConn) UnwrapReader() (io.Reader, []N.CountFunc) {
	return c.Conn, []N.CountFunc{c.recordDownload}
}

func (c *trackedConn) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	c.recordUpload(int64(n))
	return n, err
}

func (c *trackedConn) WriteBuffer(buffer *buf.Buffer) error {
	// Capture length before WriteBuffer consumes and releases the buffer.
	upload := int64(buffer.Len())
	err := c.Conn.WriteBuffer(buffer)
	if err == nil {
		c.recordUpload(upload)
	}
	return err
}

func (c *trackedConn) UnwrapWriter() (io.Writer, []N.CountFunc) {
	return c.Conn, []N.CountFunc{c.recordUpload}
}

func (c *trackedConn) Upstream() any {
	return c.Conn
}

func (c *trackedConn) Close() error {
	requestMonitor.finishDial(c.req)
	return c.Conn.Close()
}

type trackedPacketConn struct {
	constant.PacketConn
	isProxy bool
	req     *pendingRequest
}

func newTrackedPacketConn(
	pc constant.PacketConn,
	isProxy bool,
	meta *constant.Metadata,
) constant.PacketConn {
	return &trackedPacketConn{
		PacketConn: pc,
		isProxy:    isProxy,
		req:        requestMonitor.registerDial(meta, pc.Chains(), pc.ProviderChains()),
	}
}

func (c *trackedPacketConn) recordDownload(size int64) {
	if size <= 0 {
		return
	}
	if c.isProxy {
		proxyTraffic.recordDownload(size)
	}
	if c.req != nil {
		c.req.download.Add(size)
	}
}

func (c *trackedPacketConn) recordUpload(size int64) {
	if size <= 0 {
		return
	}
	if c.isProxy {
		proxyTraffic.recordUpload(size)
	}
	if c.req != nil {
		c.req.upload.Add(size)
	}
}

func (c *trackedPacketConn) ReadFrom(b []byte) (int, net.Addr, error) {
	n, addr, err := c.PacketConn.ReadFrom(b)
	c.recordDownload(int64(n))
	return n, addr, err
}

func (c *trackedPacketConn) WaitReadFrom() ([]byte, func(), net.Addr, error) {
	data, put, addr, err := c.PacketConn.WaitReadFrom()
	c.recordDownload(int64(len(data)))
	return data, put, addr, err
}

func (c *trackedPacketConn) WriteTo(b []byte, addr net.Addr) (int, error) {
	n, err := c.PacketConn.WriteTo(b, addr)
	c.recordUpload(int64(n))
	return n, err
}

func (c *trackedPacketConn) Upstream() any {
	return c.PacketConn
}

func (c *trackedPacketConn) Close() error {
	requestMonitor.finishDial(c.req)
	return c.PacketConn.Close()
}

type trackedProxy struct {
	constant.Proxy
}

func wrapConfigProxies(cfg *config.Config) {
	if cfg == nil || len(cfg.Proxies) == 0 {
		return
	}
	for name, proxy := range cfg.Proxies {
		if proxy == nil {
			continue
		}
		if _, already := proxy.(*trackedProxy); already {
			continue
		}
		cfg.Proxies[name] = &trackedProxy{Proxy: proxy}
	}
}

func withWrappedDial(ctx context.Context) context.Context {
	return context.WithValue(ctx, wrappedDialKey{}, true)
}

func (p *trackedProxy) DialContext(ctx context.Context, metadata *constant.Metadata) (constant.Conn, error) {
	if ctx.Value(wrappedDialKey{}) != nil {
		return p.Proxy.DialContext(ctx, metadata)
	}
	conn, err := p.Proxy.DialContext(withWrappedDial(ctx), metadata)
	if err != nil || conn == nil {
		return conn, err
	}
	return newTrackedConn(conn, isProxyChain(conn.Chains()), metadata), nil
}

func (p *trackedProxy) ListenPacketContext(ctx context.Context, metadata *constant.Metadata) (constant.PacketConn, error) {
	if ctx.Value(wrappedDialKey{}) != nil {
		return p.Proxy.ListenPacketContext(ctx, metadata)
	}
	pc, err := p.Proxy.ListenPacketContext(withWrappedDial(ctx), metadata)
	if err != nil || pc == nil {
		return pc, err
	}
	return newTrackedPacketConn(pc, isProxyChain(pc.Chains()), metadata), nil
}

func (p *trackedProxy) URLTest(
	ctx context.Context,
	url string,
	expectedStatus utils.IntRanges[uint16],
) (uint16, error) {
	delay, err := p.Proxy.URLTest(withWrappedDial(ctx), url, expectedStatus)
	publishDelayResult(p.Name(), url, delay, err)
	return delay, err
}

func publishDelayResult(name, url string, delay uint16, err error) {
	result := delay
	if err != nil {
		result = 0
	}
	recordObservedDelay(name, url, time.Now())
	if !shouldPublishDelay(result) {
		return
	}
	sendMessage(Message{
		Type: DelayMessage,
		Data: &Delay{
			Url:   url,
			Name:  name,
			Value: delayValue(result),
		},
	})
}

type delaySampleKey struct {
	name string
	url  string
}

var (
	observerMu          sync.Mutex
	observerCancel      context.CancelFunc
	seenDelayTimestamps = make(map[delaySampleKey]time.Time)
	seenProviderUpdates = make(map[string]time.Time)
)

func recordObservedDelay(name, url string, measuredAt time.Time) {
	observerMu.Lock()
	defer observerMu.Unlock()
	key := delaySampleKey{name: name, url: url}
	if prev, ok := seenDelayTimestamps[key]; !ok || measuredAt.After(prev) {
		seenDelayTimestamps[key] = measuredAt
	}
}

func scanDelayHistories() {
	if !isInit.Load() {
		return
	}
	for name, proxy := range allProxies() {
		if proxy == nil {
			continue
		}
		for testURL, state := range proxy.ExtraDelayHistories() {
			if len(state.History) == 0 {
				continue
			}
			latest := state.History[len(state.History)-1]
			key := delaySampleKey{name: name, url: testURL}
			observerMu.Lock()
			prev, seen := seenDelayTimestamps[key]
			isNewer := !seen || latest.Time.After(prev)
			if isNewer {
				seenDelayTimestamps[key] = latest.Time
			}
			observerMu.Unlock()

			if !isNewer {
				continue
			}
			if !shouldPublishDelay(latest.Delay) {
				continue
			}
			sendMessage(Message{
				Type: DelayMessage,
				Data: &Delay{
					Url:   testURL,
					Name:  name,
					Value: delayValue(latest.Delay),
				},
			})
		}
	}
}

func proxyProviderSubscriptionInfo(typed *provider.ProxySetProvider) *provider.SubscriptionInfo {
	if typed == nil {
		return nil
	}
	if raw := cachefile.Cache().GetSubscriptionInfo(typed.Name()); raw != "" {
		return provider.NewSubscriptionInfo(raw)
	}
	data, err := typed.MarshalJSON()
	if err != nil {
		return nil
	}
	var payload struct {
		SubscriptionInfo *provider.SubscriptionInfo `json:"subscriptionInfo"`
	}
	if err := json.Unmarshal(data, &payload); err != nil {
		return nil
	}
	return payload.SubscriptionInfo
}

func providerUpdatedAt(p cp.Provider) (time.Time, bool) {
	switch typed := p.(type) {
	case *provider.ProxySetProvider:
		return typed.UpdatedAt(), true
	case *rp.RuleSetProvider:
		return typed.UpdatedAt(), true
	default:
		return time.Time{}, false
	}
}

func notifyInitialProvidersLoaded() {
	observerMu.Lock()
	seenProviderUpdates = make(map[string]time.Time)
	observerMu.Unlock()

	loaded := false
	for name, p := range externalProviders() {
		updatedAt, ok := providerUpdatedAt(p)
		if !ok {
			continue
		}
		observerMu.Lock()
		seenProviderUpdates[name] = updatedAt
		observerMu.Unlock()
		loaded = true
		sendMessage(Message{
			Type: LoadedMessage,
			Data: name,
		})
	}
	if loaded {
		scheduleReclaimOwnership()
	}
}

func scanProviderUpdates() {
	if !isInit.Load() {
		return
	}
	loaded := false
	for name, p := range externalProviders() {
		updatedAt, ok := providerUpdatedAt(p)
		if !ok {
			continue
		}
		observerMu.Lock()
		prev, seen := seenProviderUpdates[name]
		changed := !seen || updatedAt.After(prev)
		if changed {
			seenProviderUpdates[name] = updatedAt
		}
		observerMu.Unlock()
		if changed {
			loaded = true
			sendMessage(Message{
				Type: LoadedMessage,
				Data: name,
			})
		}
	}
	if loaded {
		scheduleReclaimOwnership()
	}
}

func startRuntimeObservers() {
	observerMu.Lock()
	if observerCancel != nil {
		observerCancel()
		observerCancel = nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	observerCancel = cancel
	observerMu.Unlock()

	go runRequestMonitorLoop(ctx)
	go runBackgroundObserverLoop(ctx)
}

func stopRuntimeObservers() {
	observerMu.Lock()
	if observerCancel != nil {
		observerCancel()
		observerCancel = nil
	}
	seenDelayTimestamps = make(map[delaySampleKey]time.Time)
	seenProviderUpdates = make(map[string]time.Time)
	observerMu.Unlock()
	requestMonitor.reset()
}

func runRequestMonitorLoop(ctx context.Context) {
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-requestMonitor.notify:
			time.Sleep(15 * time.Millisecond)
			requestMonitor.scanSnapshot()
		case <-ticker.C:
			requestMonitor.scanSnapshot()
		}
	}
}

func runBackgroundObserverLoop(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			scanDelayHistories()
			scanProviderUpdates()
		}
	}
}

var (
	geoUpdaterMu     sync.Mutex
	geoUpdaterCancel context.CancelFunc
)

func defaultRegisterGeoUpdater() {
	geoUpdaterMu.Lock()
	if geoUpdaterCancel != nil {
		geoUpdaterCancel()
		geoUpdaterCancel = nil
	}
	interval := updater.GeoUpdateInterval()
	if interval <= 0 {
		geoUpdaterMu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	geoUpdaterCancel = cancel
	geoUpdaterMu.Unlock()

	go runGeoUpdaterLoop(ctx, time.Duration(interval)*time.Hour)
}

func defaultStopGeoUpdater() {
	geoUpdaterMu.Lock()
	if geoUpdaterCancel != nil {
		geoUpdaterCancel()
		geoUpdaterCancel = nil
	}
	geoUpdaterMu.Unlock()
}

func runGeoUpdaterLoop(ctx context.Context, interval time.Duration) {
	if lastUpdate, err := lastGeoUpdateTime(); err == nil {
		if lastUpdate.Add(interval).Before(time.Now()) {
			runAutoGeoDatabases()
		}
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			runAutoGeoDatabases()
		}
	}
}

func lastGeoUpdateTime() (time.Time, error) {
	files := []string{
		constant.Path.GeoIP(),
		constant.Path.MMDB(),
		constant.Path.ASN(),
		constant.Path.GeoSite(),
	}
	for _, file := range files {
		info, err := os.Stat(file)
		if err == nil {
			return info.ModTime(), nil
		}
	}
	return time.Time{}, os.ErrNotExist
}

func tryClaimAutoGeoUpdate(geoType string) bool {
	key := geoUpdateScope + geoType
	updateMu.Lock()
	defer updateMu.Unlock()
	if updateInFlight[key] {
		return false
	}
	updateInFlight[key] = true
	geoHookClaims[key] = true
	return true
}

func runAutoGeoDatabases() {
	var wg sync.WaitGroup
	run := func(geoType string) {
		update, exist := geoResourceUpdaters[geoType]
		if !exist || !tryClaimAutoGeoUpdate(geoType) {
			return
		}
		wg.Add(1)
		safeGoDetached("autoGeoUpdate("+geoType+")", func() {
			defer wg.Done()
			_ = runGeoResourceUpdate(geoType, update, true)
		})
	}
	if geodata.GeoIpEnable() {
		if geodata.GeodataMode() {
			run("GEOIP")
		} else {
			run("MMDB")
		}
	}
	if geodata.ASNEnable() {
		run("ASN")
	}
	if geodata.GeoSiteEnable() {
		run("GEOSITE")
	}
	wg.Wait()
}

func geoFilePath(geoType string) string {
	switch geoType {
	case "MMDB":
		return constant.Path.MMDB()
	case "ASN":
		return constant.Path.ASN()
	case "GEOIP":
		return constant.Path.GeoIP()
	case "GEOSITE":
		return constant.Path.GeoSite()
	default:
		return ""
	}
}

func fileSHA256(path string) ([sha256.Size]byte, bool) {
	var zero [sha256.Size]byte
	if path == "" {
		return zero, false
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return zero, false
	}
	return sha256.Sum256(data), true
}

func onGeoUpdateEvent(geoType string, updating, skipped bool, updateErr error) {
	if updating {
		claimGeoUpdateFromHook(geoType)
	} else {
		releaseGeoUpdateFromHook(geoType)
		scheduleReclaimOwnership()
	}
	status := GeoUpdateStatus{
		Type:     geoType,
		Updating: updating,
		Skipped:  skipped,
	}
	if updateErr != nil {
		status.Error = updateErr.Error()
	}
	sendMessage(Message{
		Type: GeoUpdateMessage,
		Data: status,
	})
}

func runGeoResourceUpdate(geoType string, update func() error, fromHook bool) error {
	if update == nil {
		return nil
	}
	targetPath := geoFilePath(geoType)
	beforeHash, hadBefore := fileSHA256(targetPath)
	if fromHook {
		onGeoUpdateEvent(geoType, true, false, nil)
	} else {
		sendMessage(Message{
			Type: GeoUpdateMessage,
			Data: GeoUpdateStatus{
				Type:     geoType,
				Updating: true,
			},
		})
	}

	err := update()
	skipped := false
	if err == nil && hadBefore {
		if afterHash, hasAfter := fileSHA256(targetPath); hasAfter && beforeHash == afterHash {
			skipped = true
		}
	}

	if fromHook {
		onGeoUpdateEvent(geoType, false, skipped, err)
	} else {
		scheduleReclaimOwnership()
		status := GeoUpdateStatus{
			Type:     geoType,
			Updating: false,
			Skipped:  skipped,
		}
		if err != nil {
			status.Error = err.Error()
		}
		sendMessage(Message{
			Type: GeoUpdateMessage,
			Data: status,
		})
	}
	return err
}

func stopListeners() {
	listener.PatchInboundListeners(nil, tunnel.Tunnel, true)
	listener.PatchTunnel(nil, tunnel.Tunnel)
	listener.ReCreateHTTP(0, tunnel.Tunnel)
	listener.ReCreateSocks(0, tunnel.Tunnel)
	listener.ReCreateRedir(0, tunnel.Tunnel)
	listener.ReCreateTProxy(0, tunnel.Tunnel)
	listener.ReCreateMixed(0, tunnel.Tunnel)
	listener.ReCreateShadowSocks("", tunnel.Tunnel)
	listener.ReCreateVmess("", tunnel.Tunnel)
	listener.ReCreateTuic(LC.TuicServer{}, tunnel.Tunnel)
	if runtime.GOOS != "android" {
		listener.ReCreateTun(LC.Tun{Enable: false}, tunnel.Tunnel)
		listener.Cleanup()
	}
}
