package main

import (
	"cmp"
	"context"
	"errors"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"slices"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/iface"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

var (
	logMu         sync.Mutex
	logSubscriber observable.Subscription[log.Event]
	logCancel     context.CancelFunc
)

func handleInitClash(params *InitParams) bool {
	configMu.Lock()
	defer configMu.Unlock()
	sdkVersion.Store(int32(params.Version))
	constant.SetHomeDir(params.HomeDir)
	initOwnership(params.HomeDir)
	isInit.Store(true)
	return true
}

func handleStartListener() bool {
	configMu.Lock()
	defer configMu.Unlock()
	isRunning.Store(true)
	updateListeners(currentConfig)
	resolver.ResetConnection()
	return true
}

func handleStopListener() bool {
	configMu.Lock()
	defer configMu.Unlock()
	isRunning.Store(false)
	stopListeners()
	resolver.ResetConnection()
	return true
}

func handleGetIsInit() bool {
	return isInit.Load()
}

func resolveMihomoVersion(injectedVersion string, readBuildInfo func() (*debug.BuildInfo, bool)) string {
	if info, ok := readBuildInfo(); ok {
		for _, dep := range info.Deps {
			if dep.Path != "github.com/metacubex/mihomo" {
				continue
			}
			if dep.Replace != nil {
				if dep.Replace.Version != "" && dep.Replace.Version != "(devel)" {
					return dep.Replace.Version
				}
				break
			}
			if dep.Version != "" && dep.Version != "(devel)" {
				return dep.Version
			}
		}
	}
	if injectedVersion != "" &&
		injectedVersion != "1.10.0" &&
		injectedVersion != "unknown version" {
		return injectedVersion
	}
	return ""
}

func handleGetCoreVersion() string {
	return resolveMihomoVersion(constant.Version, debug.ReadBuildInfo)
}

func handleForceGC() {
	log.Infoln("[APP] request force GC")
	invalidateAllProxies()
	runtime.GC()
	if runtime.GOOS == "android" {
		debug.FreeOSMemory()
	}
}

func handleShutdown() bool {
	handleStopLog()
	stopRuntimeObservers()

	configMu.Lock()
	isRunning.Store(false)
	stopListeners()
	stopGeoUpdater()
	executor.Shutdown()
	currentConfig = nil
	isInit.Store(false)
	clearTunnelSnapshots()
	proxyTraffic.Reset()
	configMu.Unlock()

	handleForceGC()
	return true
}

func handleValidateConfig(path string) string {
	buf, err := os.ReadFile(path)
	if err != nil {
		return err.Error()
	}
	if _, err = config.UnmarshalRawConfig(buf); err != nil {
		return err.Error()
	}
	return ""
}

const globalProxyName = "GLOBAL"

func isProxyGroupType(adapterType constant.AdapterType) bool {
	switch adapterType {
	case constant.Selector, constant.URLTest, constant.Fallback, constant.Relay, constant.LoadBalance:
		return true
	default:
		return false
	}
}

func proxyGroupNames(
	nameList []string,
	typeOf func(name string) (constant.AdapterType, bool),
) []string {
	hasGlobal := false
	names := make([]string, 0, len(nameList)+1)

	for _, name := range nameList {
		if name == globalProxyName {
			hasGlobal = true
		}
		adapterType, ok := typeOf(name)
		if !ok || !isProxyGroupType(adapterType) {
			continue
		}
		names = append(names, name)
	}

	if !hasGlobal {
		if adapterType, ok := typeOf(globalProxyName); ok && isProxyGroupType(adapterType) {
			names = append([]string{globalProxyName}, names...)
		}
	}

	return names
}

func handleGetProxies() ProxiesData {
	proxies := allProxies()

	allNames := proxyGroupNames(proxyNameList(), func(name string) (constant.AdapterType, bool) {
		p, ok := proxies[name]
		if !ok || p == nil {
			return 0, false
		}
		return p.Type(), true
	})

	return ProxiesData{
		All:     allNames,
		Proxies: proxies,
	}
}

var (
	errGroupNotFound    = errors.New("Not found group")
	errGroupInvalidType = errors.New("Group has invalid proxy type")
	errGroupNotSelect   = errors.New("Group is not selectable")
)

func lookupProxy(name string) constant.Proxy {
	return allProxies()[name]
}

func selectableGroup(groupName string) (outboundgroup.SelectAble, error) {
	group := lookupProxy(groupName)
	if group == nil {
		return nil, errGroupNotFound
	}
	adapterProxy := group.Adapter()
	if adapterProxy == nil {
		return nil, errGroupInvalidType
	}
	selector, ok := adapterProxy.(outboundgroup.SelectAble)
	if !ok {
		return nil, errGroupNotSelect
	}
	return selector, nil
}

func handleChangeProxy(params *ChangeProxyParams) string {
	selectMu.Lock()
	defer selectMu.Unlock()

	selector, err := selectableGroup(params.GroupName)
	if err != nil {
		return err.Error()
	}
	if params.ProxyName == "" {
		selector.ForceSet(params.ProxyName)
		return ""
	}
	if err := selector.Set(params.ProxyName); err != nil {
		return err.Error()
	}
	return ""
}

func handleGetTraffic(onlyStatisticsProxy bool) Traffic {
	var up, down int64
	if onlyStatisticsProxy {
		up, down = proxyTraffic.Now()
	} else {
		up, down = statistic.DefaultManager.Now()
	}
	return Traffic{
		Up:   up,
		Down: down,
	}
}

func handleGetTotalTraffic(onlyStatisticsProxy bool) Traffic {
	var up, down int64
	if onlyStatisticsProxy {
		up, down = proxyTraffic.Total()
	} else {
		up, down = statistic.DefaultManager.Total()
	}
	return Traffic{
		Up:   up,
		Down: down,
	}
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
	proxyTraffic.Reset()
}

func delayValue(delay uint16) int32 {
	if delay == 0 {
		return -1
	}
	return int32(delay)
}

var anyDelayTestStatus utils.IntRanges[uint16]

func delayTestTimeout(milliseconds int64) time.Duration {
	if milliseconds <= 0 {
		return defaultDelayTestTimeout
	}
	return time.Duration(milliseconds) * time.Millisecond
}

var missingDelayTestProxyAt atomic.Int64

// A delay test against a name the tunnel does not know is what an apply that
// fell back to the default config looks like from the outside: the profile
// still lists every node and every one of them reports Timeout. Say so, once a
// second rather than once per node, so the log names the real failure.
func reportMissingDelayTestProxy(name string) {
	now := time.Now().UnixNano()
	last := missingDelayTestProxyAt.Load()
	if last != 0 && now-last < int64(time.Second) {
		return
	}
	if !missingDelayTestProxyAt.CompareAndSwap(last, now) {
		return
	}
	logError("delay test: %q is not part of the applied config", name)
}

func handleTestDelay(params *TestDelayParams) *Delay {
	url := params.TestUrl
	if url == "" {
		url = currentTestURL()
	}
	delayData := &Delay{
		Name:  params.ProxyName,
		Url:   url,
		Value: -1,
	}

	proxy := lookupProxy(params.ProxyName)
	if proxy == nil {
		reportMissingDelayTestProxy(params.ProxyName)
		return delayData
	}

	timeout := delayTestTimeout(params.Timeout)

	// Queueing for a slot and probing the node each get the full timeout.
	// Sharing one deadline meant a node that waited four seconds behind a
	// saturated semaphore had one second left to connect, so a bulk test of a
	// large subscription reported Timeout for whatever happened to be at the
	// back of the queue.
	queueCtx, cancelQueue := context.WithTimeout(context.Background(), timeout)
	granted := acquireDelayTestSlot(queueCtx)
	cancelQueue()
	if !granted {
		return nil
	}
	defer releaseDelayTestSlot()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	delay, err := proxy.URLTest(withWrappedDial(ctx), url, anyDelayTestStatus)
	if _, tracked := proxy.(*trackedProxy); !tracked {
		publishDelayResult(proxy.Name(), url, delay, err)
	}
	if err != nil {
		return delayData
	}

	delayData.Value = delayValue(delay)
	return delayData
}

func handleGetConnections() *statistic.Snapshot {
	return statistic.DefaultManager.Snapshot()
}

func handleCloseConnections() bool {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
	return true
}

func handleResetConnections() bool {
	resolver.ResetConnection()
	return true
}

func handleCloseConnection(connectionId string) bool {
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}

func handleGetExternalProviders() []ExternalProvider {
	providers := externalProviders()
	eps := make([]ExternalProvider, 0, len(providers))
	for _, p := range providers {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	slices.SortFunc(eps, func(a, b ExternalProvider) int {
		return cmp.Compare(a.Name, b.Name)
	})
	return eps
}

func handleGetExternalProvider(externalProviderName string) *ExternalProvider {
	p, exist := lookupExternalProvider(externalProviderName)
	if !exist {
		return nil
	}
	externalProvider, err := toExternalProvider(p)
	if err != nil {
		return nil
	}
	return externalProvider
}

var geoResourceUpdaters = map[string]func() error{
	"MMDB":    updater.UpdateMMDB,
	"ASN":     updater.UpdateASN,
	"GEOIP":   updater.UpdateGeoIp,
	"GEOSITE": updater.UpdateGeoSite,
}

const (
	geoUpdateScope      = "geo:"
	providerUpdateScope = "provider:"
)

var (
	updateMu       sync.Mutex
	updateInFlight = map[string]bool{}
	geoHookClaims  = map[string]bool{}
)

func claimUpdate(key string) bool {
	updateMu.Lock()
	defer updateMu.Unlock()
	if updateInFlight[key] {
		return false
	}
	updateInFlight[key] = true
	return true
}

func releaseUpdate(key string) {
	updateMu.Lock()
	defer updateMu.Unlock()
	delete(updateInFlight, key)
	delete(geoHookClaims, key)
}

func claimGeoUpdate(geoType string) bool {
	return claimUpdate(geoUpdateScope + geoType)
}

func releaseGeoUpdate(geoType string) {
	releaseUpdate(geoUpdateScope + geoType)
}

func claimGeoUpdateFromHook(geoType string) {
	key := geoUpdateScope + geoType
	updateMu.Lock()
	defer updateMu.Unlock()
	if updateInFlight[key] {
		return
	}
	updateInFlight[key] = true
	geoHookClaims[key] = true
}

func releaseGeoUpdateFromHook(geoType string) {
	key := geoUpdateScope + geoType
	updateMu.Lock()
	defer updateMu.Unlock()
	if !geoHookClaims[key] {
		return
	}
	delete(geoHookClaims, key)
	delete(updateInFlight, key)
}

func handleUpdateGeoData(geoType string) string {
	update, exist := geoResourceUpdaters[geoType]
	if !exist {
		logError("updateGeoData: unknown geo resource %q", geoType)
		return "unknown geo resource: " + geoType
	}
	if !claimGeoUpdate(geoType) {
		return "geo update already in progress: " + geoType
	}
	safeGoDetached("updateGeoData("+geoType+")", func() {
		defer releaseGeoUpdate(geoType)
		if err := runGeoResourceUpdate(geoType, update, false); err != nil {
			logError("updateGeoData(%s) error: %v", geoType, err)
		}
	})
	return ""
}

func providerRequestErrorCode(err error) string {
	message := err.Error()
	if len(message) >= 4 && message[3] == ' ' {
		status, parseErr := strconv.Atoi(message[:3])
		if parseErr == nil && status >= 100 && status <= 599 {
			return "request_bad_response"
		}
	}
	var urlError *url.Error
	var networkError net.Error
	if errors.Is(err, context.DeadlineExceeded) ||
		errors.As(err, &urlError) ||
		errors.As(err, &networkError) {
		return "request_error"
	}
	return ""
}

func providerMethodError(code, providerName string, err error) *MethodError {
	return &MethodError{
		Code:    code,
		Message: err.Error(),
		Details: map[string]any{"providerName": providerName},
	}
}

func handleUpdateExternalProvider(providerName string) *MethodError {
	p, exist := lookupExternalProvider(providerName)
	if !exist {
		return providerMethodError(
			"provider_not_found",
			providerName,
			errors.New("external provider does not exist"),
		)
	}
	key := providerUpdateScope + providerName
	if !claimUpdate(key) {
		return providerMethodError(
			"provider_updating",
			providerName,
			errors.New("external provider is updating"),
		)
	}
	defer releaseUpdate(key)
	if err := p.Update(); err != nil {
		code := providerRequestErrorCode(err)
		if code == "" {
			code = "provider_update_error"
		}
		return providerMethodError(code, providerName, err)
	}
	return nil
}

func handleSideLoadExternalProvider(providerName string, data []byte) *MethodError {
	p, exist := lookupExternalProvider(providerName)
	if !exist {
		return providerMethodError(
			"provider_not_found",
			providerName,
			errors.New("external provider does not exist"),
		)
	}
	key := providerUpdateScope + providerName
	if !claimUpdate(key) {
		return providerMethodError(
			"provider_updating",
			providerName,
			errors.New("external provider is updating"),
		)
	}
	defer releaseUpdate(key)
	if err := sideUpdateExternalProvider(p, data); err != nil {
		return providerMethodError("provider_update_error", providerName, err)
	}
	return nil
}

// defaultRefreshHealthChecks re-probes every proxy provider off the calling
// thread. Providers coalesce concurrent checks internally, so an extra call
// costs nothing when one is already running.
func defaultRefreshHealthChecks() {
	safeGoDetached("refreshHealthChecks", func() {
		for name, p := range providersSnapshot() {
			log.Debugln("[APP] re-checking provider %s after resume", name)
			p.HealthCheck()
		}
	})
}

var refreshHealthChecks = defaultRefreshHealthChecks

func handleSuspend(suspended bool) bool {
	wasSuspended := isSuspended.Swap(suspended)
	if suspended {
		tunnel.OnSuspend()
		return true
	}

	tunnel.OnRunning()
	// Provider health checks keep ticking through Doze, where the app has no
	// network at all, so coming back means every proxy is marked dead and every
	// delay reads Timeout. A lazy provider then skips its next tick because
	// nothing touched it in the meantime, and the whole list stays wrong until
	// the user tests by hand. Re-check now instead - but not while the
	// listeners are stopped, since the service also resumes the core on its way
	// down.
	if wasSuspended && isRunning.Load() {
		refreshHealthChecks()
	}
	return true
}

// A failure measured while the device is dozing says nothing about the node -
// the app had no network at all - and publishing it repaints the entire list as
// Timeout for a user who is not even looking. Successes still are worth having,
// whenever they happen.
func shouldPublishDelay(delay uint16) bool {
	return delay != 0 || !isSuspended.Load()
}

func handleStartLog() {
	logMu.Lock()
	if logCancel != nil {
		logCancel()
		logCancel = nil
	}
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	ctx, cancel := context.WithCancel(context.Background())
	subscriber := log.Subscribe()
	logSubscriber = subscriber
	logCancel = cancel
	logMu.Unlock()

	go func() {
		defer func() {
			logMu.Lock()
			if logSubscriber == subscriber {
				log.UnSubscribe(subscriber)
				logSubscriber = nil
				logCancel = nil
			}
			logMu.Unlock()
		}()
		for {
			select {
			case <-ctx.Done():
				return
			case logData, ok := <-subscriber:
				if !ok {
					return
				}
				if logData.LogLevel < log.Level() {
					continue
				}
				sendMessage(Message{
					Type: LogMessage,
					Data: logData,
				})
			}
		}
	}()
}

func handleStopLog() {
	logMu.Lock()
	defer logMu.Unlock()
	if logCancel != nil {
		logCancel()
		logCancel = nil
	}
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
}

func handleGetMemory() uint64 {
	return statistic.DefaultManager.Memory()
}

func handleGetInterfaces() []string {
	iface.FlushCache()
	ifaces, err := iface.Interfaces()
	if err != nil {
		return []string{}
	}
	configMu.Lock()
	tunDevice := ""
	if currentConfig != nil && currentConfig.General != nil {
		tunDevice = currentConfig.General.Tun.Device
	}
	configMu.Unlock()
	return filterPhysicalInterfaces(ifaces, tunDevice)
}

func filterPhysicalInterfaces(ifaces map[string]*iface.Interface, tunDevice string) []string {
	names := make([]string, 0, len(ifaces))
	for _, entry := range ifaces {
		if entry == nil || entry.Name == "" || (tunDevice != "" && entry.Name == tunDevice) {
			continue
		}
		if entry.Flags&net.FlagUp == 0 ||
			entry.Flags&net.FlagLoopback != 0 ||
			entry.Flags&net.FlagPointToPoint != 0 {
			continue
		}
		if len(entry.HardwareAddr) == 0 {
			continue
		}
		hasIP := false
		for _, addr := range entry.Addresses {
			ip := addr.Addr()
			if ip.IsValid() && !ip.IsLoopback() && !ip.IsLinkLocalUnicast() {
				hasIP = true
				break
			}
		}
		if !hasIP {
			continue
		}
		names = append(names, entry.Name)
	}
	slices.Sort(names)
	return names
}

func handleGetConfig(path string) (*config.RawConfig, error) {
	buf, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return config.UnmarshalRawConfig(buf)
}

func handleCrash() {
	panic("handle invoke crash")
}

func handleUpdateConfig(params *UpdateParams) string {
	if err := updateConfig(params); err != nil {
		return err.Error()
	}
	return ""
}

// The profile ID is an int64 rendered through strconv, so the last element can
// never carry a separator or a `..` — that is what keeps handleClearEffect from
// becoming a general-purpose privileged file deletion API.
func providerPaths(homeDir string, profileId int64) (root string, target string) {
	root = filepath.Join(homeDir, "profiles", "providers")
	return root, filepath.Join(root, strconv.FormatInt(profileId, 10))
}

// handleClearEffect derives the provider directory from a profile ID so the
// method cannot be used as a general-purpose privileged file deletion API.
func handleClearEffect(profileId int64) string {
	if !isInit.Load() {
		return "not initialized"
	}
	if profileId <= 0 {
		return "invalid profile id"
	}
	providersRoot, providersPath := providerPaths(constant.Path.HomeDir(), profileId)
	if err := os.RemoveAll(providersPath); err != nil {
		return err.Error()
	}
	_ = os.Remove(providersRoot)
	return ""
}

var setupConfig = applyConfig

func handleSetupConfig(params *SetupParams) string {
	if !isInit.Load() {
		return "not initialized"
	}
	if err := setupConfig(params); err != nil {
		return err.Error()
	}
	return ""
}
