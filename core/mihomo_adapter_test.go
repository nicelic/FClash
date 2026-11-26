//go:build !(android && cgo)

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/netip"
	"os"
	"path/filepath"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/common/buf"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

type stubOutAdapter struct {
	*outbound.Base
	dialFn   func(ctx context.Context, meta *constant.Metadata) (constant.Conn, error)
	packetFn func(ctx context.Context, meta *constant.Metadata) (constant.PacketConn, error)
}

func (a *stubOutAdapter) DialContext(ctx context.Context, meta *constant.Metadata) (constant.Conn, error) {
	if a.dialFn != nil {
		return a.dialFn(ctx, meta)
	}
	return nil, constant.ErrNotSupport
}

func (a *stubOutAdapter) ListenPacketContext(ctx context.Context, meta *constant.Metadata) (constant.PacketConn, error) {
	if a.packetFn != nil {
		return a.packetFn(ctx, meta)
	}
	return nil, constant.ErrNotSupport
}

func (a *stubOutAdapter) Close() error {
	return nil
}

type stubProxyProvider struct {
	name    string
	proxies []constant.Proxy
	version atomic.Uint32
}

func (p *stubProxyProvider) Name() string {
	return p.name
}

func (p *stubProxyProvider) VehicleType() cp.VehicleType {
	return cp.Compatible
}

func (p *stubProxyProvider) Type() cp.ProviderType {
	return cp.Proxy
}

func (p *stubProxyProvider) Initial() error {
	return nil
}

func (p *stubProxyProvider) Update() error {
	return nil
}

func (p *stubProxyProvider) Proxies() []constant.Proxy {
	return p.proxies
}

func (p *stubProxyProvider) Count() int {
	return len(p.proxies)
}

func (p *stubProxyProvider) Touch() {}

func (p *stubProxyProvider) HealthCheck() {}

func (p *stubProxyProvider) Version() uint32 {
	return p.version.Load()
}

func (p *stubProxyProvider) RegisterHealthCheckTask(
	_ string,
	_ utils.IntRanges[uint16],
	_ string,
	_ uint,
) {
}

func (p *stubProxyProvider) HealthCheckURL() string {
	return ""
}

type memPacketConn struct {
	mu      sync.Mutex
	inbound [][]byte
	written [][]byte
	closed  atomic.Bool
}

func (c *memPacketConn) ReadFrom(b []byte) (int, net.Addr, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if len(c.inbound) == 0 {
		return 0, nil, io.EOF
	}
	pkt := c.inbound[0]
	c.inbound = c.inbound[1:]
	n := copy(b, pkt)
	return n, &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53}, nil
}

func (c *memPacketConn) WriteTo(b []byte, _ net.Addr) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	cpBytes := append([]byte(nil), b...)
	c.written = append(c.written, cpBytes)
	return len(b), nil
}

func (c *memPacketConn) Close() error {
	c.closed.Store(true)
	return nil
}

func (c *memPacketConn) LocalAddr() net.Addr {
	return &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 10000}
}

func (c *memPacketConn) SetDeadline(_ time.Time) error      { return nil }
func (c *memPacketConn) SetReadDeadline(_ time.Time) error  { return nil }
func (c *memPacketConn) SetWriteDeadline(_ time.Time) error { return nil }

type adapterCaptureConn struct {
	mu      sync.Mutex
	written bytes.Buffer
}

func (c *adapterCaptureConn) Read(_ []byte) (int, error) {
	return 0, io.EOF
}

func (c *adapterCaptureConn) Write(p []byte) (int, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.written.Write(p)
}

func (c *adapterCaptureConn) Close() error {
	return nil
}

func (c *adapterCaptureConn) SetWriteDeadline(_ time.Time) error {
	return nil
}

func (c *adapterCaptureConn) frames(t *testing.T) [][]byte {
	t.Helper()
	c.mu.Lock()
	defer c.mu.Unlock()
	reader := bytes.NewReader(c.written.Bytes())
	var frames [][]byte
	for {
		frame, err := readFrame(reader)
		if err == io.EOF {
			return frames
		}
		if err != nil {
			t.Fatalf("readFrame error: %v", err)
		}
		frames = append(frames, frame)
	}
}

func swapAdapterConn(next ipcConn) ipcConn {
	connMu.Lock()
	defer connMu.Unlock()
	previous := conn
	conn = next
	return previous
}

type capturedMessage struct {
	Type MessageType     `json:"type"`
	Data json.RawMessage `json:"data"`
}

func decodeFramesToMessages(t *testing.T, frames [][]byte) []capturedMessage {
	t.Helper()
	var messages []capturedMessage
	for _, frame := range frames {
		var call MethodCall
		if err := json.Unmarshal(frame, &call); err != nil {
			t.Fatalf("unmarshal frame: %v", err)
		}
		if call.Method != messageMethod {
			continue
		}
		var batch []capturedMessage
		if err := json.Unmarshal(call.Arguments, &batch); err != nil {
			t.Fatalf("unmarshal message batch: %v", err)
		}
		messages = append(messages, batch...)
	}
	return messages
}

func waitForCapturedMessages(
	t *testing.T,
	fake *adapterCaptureConn,
	timeout time.Duration,
	ready func([]capturedMessage) bool,
) []capturedMessage {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for {
		msgs := decodeFramesToMessages(t, fake.frames(t))
		if ready(msgs) {
			return msgs
		}
		if time.Now().After(deadline) {
			return msgs
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func newTestProxy(name string, adapterType constant.AdapterType) (*stubOutAdapter, constant.Proxy) {
	out := &stubOutAdapter{
		Base: outbound.NewBase(outbound.BaseOption{
			Name: name,
			Addr: "127.0.0.1:443",
			Type: adapterType,
			UDP:  true,
		}),
	}
	return out, adapter.NewProxy(out)
}

func TestProxyNameListUsesDefaultProviderOrderAndSortedFallback(t *testing.T) {
	t.Cleanup(clearTunnelSnapshots)

	_, nodeB := newTestProxy("node-b", constant.Shadowsocks)
	_, nodeA := newTestProxy("node-a", constant.Shadowsocks)
	_, nodeZ := newTestProxy("node-z", constant.Shadowsocks)
	defProvider := &stubProxyProvider{
		name:    provider.ReservedName,
		proxies: []constant.Proxy{nodeZ, nodeA, nodeB},
	}

	updateTunnelProxies(
		map[string]constant.Proxy{"node-a": nodeA, "node-b": nodeB},
		map[string]cp.ProxyProvider{provider.ReservedName: defProvider},
	)
	got := proxyNameList()
	wantOrdered := []string{"node-z", "node-a", "node-b"}
	if !reflect.DeepEqual(got, wantOrdered) {
		t.Fatalf("proxyNameList() with default provider = %v, want %v", got, wantOrdered)
	}

	updateTunnelProxies(
		map[string]constant.Proxy{"node-z": nodeZ, "node-a": nodeA, "node-b": nodeB},
		nil,
	)
	got = proxyNameList()
	wantSorted := []string{"node-a", "node-b", "node-z"}
	if !reflect.DeepEqual(got, wantSorted) {
		t.Fatalf("proxyNameList() fallback = %v, want %v", got, wantSorted)
	}
}

func TestTrackedProxyAccountingAndNestedDialAvoidsDoubleCount(t *testing.T) {
	t.Cleanup(func() {
		clearTunnelSnapshots()
		proxyTraffic.Reset()
		statistic.DefaultManager.ResetStatistic()
		requestMonitor.reset()
	})
	proxyTraffic.Reset()
	statistic.DefaultManager.ResetStatistic()
	requestMonitor.reset()

	innerOut, innerProxy := newTestProxy("inner-ss", constant.Shadowsocks)
	outerOut, outerProxy := newTestProxy("outer-group", constant.Selector)
	directOut, directProxy := newTestProxy("DIRECT", constant.Direct)

	cfg := &config.Config{
		Proxies: map[string]constant.Proxy{
			"inner-ss":    innerProxy,
			"outer-group": outerProxy,
			"DIRECT":      directProxy,
		},
	}
	wrapConfigProxies(cfg)
	wrapConfigProxies(cfg)
	updateTunnelProxies(cfg.Proxies, nil)

	innerWrapped, ok := cfg.Proxies["inner-ss"].(*trackedProxy)
	if !ok {
		t.Fatal("inner-ss was not wrapped with *trackedProxy")
	}

	peerReads := make(chan []byte, 1)
	innerOut.dialFn = func(_ context.Context, _ *constant.Metadata) (constant.Conn, error) {
		c1, c2 := net.Pipe()
		go func() {
			defer func() { _ = c2.Close() }()
			first := make([]byte, 5)
			if _, err := io.ReadFull(c2, first); err != nil {
				return
			}
			_, _ = c2.Write([]byte("world!!"))
			second := make([]byte, 4)
			if _, err := io.ReadFull(c2, second); err != nil {
				return
			}
			_, _ = c2.Write([]byte("tail"))
			third := make([]byte, 3)
			_, _ = io.ReadFull(c2, third)
			peerReads <- append(append(first, second...), third...)
		}()
		return outbound.NewConn(c1, innerOut), nil
	}
	outerOut.dialFn = func(ctx context.Context, meta *constant.Metadata) (constant.Conn, error) {
		c, err := innerWrapped.DialContext(ctx, meta)
		if err != nil {
			return nil, err
		}
		c.AppendToChains(outerOut)
		return c, nil
	}
	directOut.dialFn = func(_ context.Context, _ *constant.Metadata) (constant.Conn, error) {
		c1, c2 := net.Pipe()
		go func() {
			defer func() { _ = c2.Close() }()
			tmp := make([]byte, 6)
			_, _ = io.ReadFull(c2, tmp)
		}()
		return outbound.NewConn(c1, directOut), nil
	}

	meta := &constant.Metadata{
		NetWork: constant.TCP,
		SrcIP:   netip.MustParseAddr("127.0.0.1"),
		SrcPort: 12345,
		DstPort: 443,
		Host:    "example.test",
	}

	conn, err := cfg.Proxies["outer-group"].DialContext(context.Background(), meta)
	if err != nil {
		t.Fatalf("outer DialContext error: %v", err)
	}
	if _, err := conn.Write([]byte("hello")); err != nil {
		t.Fatalf("conn.Write error: %v", err)
	}
	reply := make([]byte, 7)
	if _, err := io.ReadFull(conn, reply); err != nil {
		t.Fatalf("conn.Read error: %v", err)
	}
	wb := buf.NewSize(4)
	if _, err := wb.Write([]byte("abcd")); err != nil {
		t.Fatalf("buf.Write error: %v", err)
	}
	if err := conn.WriteBuffer(wb); err != nil {
		t.Fatalf("conn.WriteBuffer error: %v", err)
	}
	rb := buf.NewSize(4)
	if err := conn.ReadBuffer(rb); err != nil {
		rb.Release()
		t.Fatalf("conn.ReadBuffer error: %v", err)
	}
	rb.Release()

	tc, ok := conn.(*trackedConn)
	if !ok || tc.Upstream() == nil {
		t.Fatal("expected *trackedConn with non-nil Upstream")
	}
	reader, readCounts := tc.UnwrapReader()
	if reader == nil || len(readCounts) != 1 {
		t.Fatalf("UnwrapReader returned reader=%v countFns=%d, want 1", reader, len(readCounts))
	}
	readCounts[0](10)
	writer, writeCounts := tc.UnwrapWriter()
	if writer == nil || len(writeCounts) != 1 {
		t.Fatalf("UnwrapWriter returned writer=%v countFns=%d, want 1", writer, len(writeCounts))
	}
	writeCounts[0](8)

	if _, err := conn.Write([]byte("xyz")); err != nil {
		t.Fatalf("conn final Write error: %v", err)
	}
	<-peerReads

	fake := &adapterCaptureConn{}
	var msgs []capturedMessage
	func() {
		prevConn := swapAdapterConn(fake)
		defer swapAdapterConn(prevConn)
		_ = conn.Close()
		msgs = waitForCapturedMessages(t, fake, 500*time.Millisecond, func(items []capturedMessage) bool {
			return len(items) >= 1
		})
	}()

	const wantUp = int64(5 + 4 + 8 + 3)
	const wantDown = int64(7 + 4 + 10)
	gotUp, gotDown := proxyTraffic.Total()
	if gotUp != wantUp || gotDown != wantDown {
		t.Fatalf("proxyTraffic.Total() = (%d, %d), want (%d, %d)", gotUp, gotDown, wantUp, wantDown)
	}
	totalOnlyProxy := handleGetTotalTraffic(true)
	if totalOnlyProxy.Up != wantUp || totalOnlyProxy.Down != wantDown {
		t.Fatalf("handleGetTotalTraffic(true) = %+v, want {%d %d}", totalOnlyProxy, wantUp, wantDown)
	}
	var reqMsgs []capturedMessage
	for _, msg := range msgs {
		if msg.Type == RequestMessage {
			reqMsgs = append(reqMsgs, msg)
		}
	}
	if len(reqMsgs) != 1 {
		t.Fatalf("emitted close-fallback RequestMessages = %d (%v), want 1", len(reqMsgs), msgs)
	}
	var reqInfo struct {
		Upload   int64 `json:"upload"`
		Download int64 `json:"download"`
	}
	if err := json.Unmarshal(reqMsgs[0].Data, &reqInfo); err != nil {
		t.Fatalf("unmarshal TrackerInfo: %v", err)
	}
	if reqInfo.Upload != wantUp || reqInfo.Download != wantDown {
		t.Fatalf("RequestMessage traffic = (%d, %d), want (%d, %d)", reqInfo.Upload, reqInfo.Download, wantUp, wantDown)
	}

	drainCapture := &adapterCaptureConn{}
	var drainMsgs []capturedMessage
	func() {
		prevDrain := swapAdapterConn(drainCapture)
		defer swapAdapterConn(prevDrain)

		dConn, err := cfg.Proxies["DIRECT"].DialContext(context.Background(), meta)
		if err != nil {
			t.Fatalf("DIRECT DialContext error: %v", err)
		}
		_, _ = dConn.Write([]byte("direct"))
		_ = dConn.Close()
		afterDirectUp, afterDirectDown := proxyTraffic.Total()
		if afterDirectUp != wantUp || afterDirectDown != wantDown {
			t.Fatalf("DIRECT dial polluted proxyTraffic: (%d, %d), want (%d, %d)", afterDirectUp, afterDirectDown, wantUp, wantDown)
		}

		memPC := &memPacketConn{inbound: [][]byte{[]byte("pkt-in-1"), []byte("pkt-in-2")}}
		innerOut.packetFn = func(_ context.Context, _ *constant.Metadata) (constant.PacketConn, error) {
			return outbound.NewPacketConn(memPC, innerOut), nil
		}
		pc, err := cfg.Proxies["inner-ss"].ListenPacketContext(context.Background(), meta)
		if err != nil {
			t.Fatalf("ListenPacketContext error: %v", err)
		}
		if trackedPC, ok := pc.(*trackedPacketConn); !ok || trackedPC.Upstream() == nil {
			t.Fatalf("expected *trackedPacketConn with non-nil Upstream")
		}
		bufPkt := make([]byte, 16)
		n, _, err := pc.ReadFrom(bufPkt)
		if err != nil || n != 8 {
			t.Fatalf("Packet ReadFrom = (%d, %v), want (8, nil)", n, err)
		}
		data, put, _, err := pc.WaitReadFrom()
		if err != nil || len(data) != 8 {
			t.Fatalf("Packet WaitReadFrom = (%d, %v), want (8, nil)", len(data), err)
		}
		if put != nil {
			put()
		}
		if _, err := pc.WriteTo([]byte("pkt-out"), &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 53}); err != nil {
			t.Fatalf("Packet WriteTo error: %v", err)
		}
		_ = pc.Close()
		if !memPC.closed.Load() {
			t.Fatal("trackedPacketConn.Close did not close underlying packet conn")
		}
		pktUp, pktDown := proxyTraffic.Total()
		if pktUp != wantUp+7 || pktDown != wantDown+16 {
			t.Fatalf("after packet conn proxyTraffic = (%d, %d), want (%d, %d)", pktUp, pktDown, wantUp+7, wantDown+16)
		}

		drainMsgs = waitForCapturedMessages(t, drainCapture, 500*time.Millisecond, func(items []capturedMessage) bool {
			return len(items) >= 2
		})
	}()
	if len(drainMsgs) < 2 {
		t.Fatalf("expected direct + packet close RequestMessages, got %d", len(drainMsgs))
	}
}

func TestRequestMonitorDedupsSnapshotTrackerBeforeClose(t *testing.T) {
	t.Cleanup(func() {
		clearTunnelSnapshots()
		requestMonitor.reset()
		statistic.DefaultManager.ResetStatistic()
		proxyTraffic.Reset()
	})
	requestMonitor.reset()
	proxyTraffic.Reset()

	out, prx := newTestProxy("ss-dedup", constant.Shadowsocks)
	cfg := &config.Config{Proxies: map[string]constant.Proxy{"ss-dedup": prx}}
	wrapConfigProxies(cfg)
	updateTunnelProxies(cfg.Proxies, nil)

	c1, c2 := net.Pipe()
	t.Cleanup(func() { _ = c2.Close() })
	out.dialFn = func(_ context.Context, _ *constant.Metadata) (constant.Conn, error) {
		return outbound.NewConn(c1, out), nil
	}

	meta := &constant.Metadata{
		NetWork: constant.TCP,
		SrcIP:   netip.MustParseAddr("10.0.0.2"),
		SrcPort: 54321,
		DstPort: 443,
		Host:    "dedup.test",
	}

	conn, err := cfg.Proxies["ss-dedup"].DialContext(context.Background(), meta)
	if err != nil {
		t.Fatalf("DialContext error: %v", err)
	}

	fake := &adapterCaptureConn{}
	prevConn := swapAdapterConn(fake)
	defer swapAdapterConn(prevConn)

	tracker := statistic.NewTCPTracker(conn, statistic.DefaultManager, meta.Clone(), nil, 0, 0, false)
	defer func() { _ = tracker.Close() }()

	requestMonitor.scanSnapshot()
	_ = tracker.Close()

	msgs := waitForCapturedMessages(t, fake, 500*time.Millisecond, func(items []capturedMessage) bool {
		return len(items) >= 1
	})
	time.Sleep(60 * time.Millisecond)
	msgs = decodeFramesToMessages(t, fake.frames(t))
	reqCount := 0
	for _, msg := range msgs {
		if msg.Type != RequestMessage {
			continue
		}
		var info struct {
			Metadata struct {
				Host string `json:"host"`
			} `json:"metadata"`
		}
		_ = json.Unmarshal(msg.Data, &info)
		if info.Metadata.Host == "dedup.test" {
			reqCount++
		}
	}
	if reqCount != 1 {
		t.Fatalf("RequestMessage count for dedup.test = %d, want 1 (snapshot + close must dedup)", reqCount)
	}
}

func TestScanDelayHistoriesURLTestAndShouldPublishDelay(t *testing.T) {
	t.Cleanup(func() {
		clearTunnelSnapshots()
		isInit.Store(false)
		isSuspended.Store(false)
		stopRuntimeObservers()
		proxyTraffic.Reset()
		requestMonitor.reset()
	})
	isSuspended.Store(false)
	isInit.Store(true)
	stopRuntimeObservers()

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	defer srv.Close()

	out, prx := newTestProxy("node-urltest", constant.Shadowsocks)
	out.dialFn = func(ctx context.Context, _ *constant.Metadata) (constant.Conn, error) {
		var d net.Dialer
		nc, err := d.DialContext(ctx, "tcp", srv.Listener.Addr().String())
		if err != nil {
			return nil, err
		}
		return outbound.NewConn(nc, out), nil
	}
	cfg := &config.Config{Proxies: map[string]constant.Proxy{"node-urltest": prx}}
	wrapConfigProxies(cfg)
	updateTunnelProxies(cfg.Proxies, nil)

	fake := &adapterCaptureConn{}
	prevConn := swapAdapterConn(fake)
	defer swapAdapterConn(prevConn)

	delay, err := cfg.Proxies["node-urltest"].URLTest(context.Background(), srv.URL, nil)
	if err != nil || delay == 0 {
		t.Fatalf("URLTest = (%d, %v), want (>0, nil)", delay, err)
	}

	msgs := waitForCapturedMessages(t, fake, 500*time.Millisecond, func(items []capturedMessage) bool {
		return len(items) >= 1
	})
	if len(msgs) == 0 || msgs[0].Type != DelayMessage {
		t.Fatalf("expected DelayMessage from URLTest, got %+v", msgs)
	}

	scanDelayHistories()
	time.Sleep(60 * time.Millisecond)
	afterScan := decodeFramesToMessages(t, fake.frames(t))
	delayCount := 0
	for _, msg := range afterScan {
		if msg.Type != DelayMessage {
			continue
		}
		var d Delay
		_ = json.Unmarshal(msg.Data, &d)
		if d.Name == "node-urltest" {
			delayCount++
		}
	}
	if delayCount != 1 {
		t.Fatalf("delayCount = %d after scanDelayHistories, want 1", delayCount)
	}
	if up, down := proxyTraffic.Total(); up != 0 || down != 0 {
		t.Fatalf("URLTest leaked bytes into proxyTraffic: (%d, %d)", up, down)
	}

	if shouldPublishDelay(0) != true {
		t.Fatal("shouldPublishDelay(0) while awake = false, want true")
	}
	isSuspended.Store(true)
	if shouldPublishDelay(0) != false {
		t.Fatal("shouldPublishDelay(0) while suspended = true, want false")
	}
	if shouldPublishDelay(25) != true {
		t.Fatal("shouldPublishDelay(25) while suspended = false, want true")
	}
}

func TestGeoUpdaterRegistrationCancellationAndUpdateMessages(t *testing.T) {
	t.Cleanup(func() {
		defaultStopGeoUpdater()
		updater.SetGeoUpdateInterval(0)
	})

	updater.SetGeoUpdateInterval(0)
	defaultRegisterGeoUpdater()
	geoUpdaterMu.Lock()
	if geoUpdaterCancel != nil {
		geoUpdaterMu.Unlock()
		t.Fatal("geoUpdaterCancel must be nil when interval <= 0")
	}
	geoUpdaterMu.Unlock()

	updater.SetGeoUpdateInterval(12)
	defaultRegisterGeoUpdater()
	geoUpdaterMu.Lock()
	firstCancel := geoUpdaterCancel
	geoUpdaterMu.Unlock()
	if firstCancel == nil {
		t.Fatal("geoUpdaterCancel is nil after registering interval > 0")
	}

	defaultRegisterGeoUpdater()
	geoUpdaterMu.Lock()
	secondCancel := geoUpdaterCancel
	geoUpdaterMu.Unlock()
	if secondCancel == nil {
		t.Fatal("second geoUpdaterCancel is nil")
	}

	defaultStopGeoUpdater()
	geoUpdaterMu.Lock()
	afterStop := geoUpdaterCancel
	geoUpdaterMu.Unlock()
	if afterStop != nil {
		t.Fatal("geoUpdaterCancel was not cleared by defaultStopGeoUpdater")
	}

	prevHome := constant.Path.HomeDir()
	t.Cleanup(func() { constant.SetHomeDir(prevHome) })
	tmpDir := t.TempDir()
	constant.SetHomeDir(tmpDir)
	mmdbPath := constant.Path.MMDB()
	if err := os.WriteFile(mmdbPath, []byte("v1"), 0o600); err != nil {
		t.Fatalf("write mmdb: %v", err)
	}

	fake := &adapterCaptureConn{}
	prevConn := swapAdapterConn(fake)
	defer swapAdapterConn(prevConn)

	if err := runGeoResourceUpdate("MMDB", func() error { return nil }, false); err != nil {
		t.Fatalf("unchanged update error: %v", err)
	}
	if err := runGeoResourceUpdate("MMDB", func() error {
		return os.WriteFile(mmdbPath, []byte("v2"), 0o600)
	}, false); err != nil {
		t.Fatalf("changed update error: %v", err)
	}
	wantErr := errors.New("download failed")
	if err := runGeoResourceUpdate("MMDB", func() error { return wantErr }, false); !errors.Is(err, wantErr) {
		t.Fatalf("error update returned %v, want %v", err, wantErr)
	}

	msgs := waitForCapturedMessages(t, fake, 500*time.Millisecond, func(items []capturedMessage) bool {
		count := 0
		for _, item := range items {
			if item.Type == GeoUpdateMessage {
				count++
			}
		}
		return count >= 6
	})
	var statuses []GeoUpdateStatus
	for _, msg := range msgs {
		if msg.Type != GeoUpdateMessage {
			continue
		}
		var st GeoUpdateStatus
		_ = json.Unmarshal(msg.Data, &st)
		statuses = append(statuses, st)
	}
	if len(statuses) < 6 {
		t.Fatalf("captured %d GeoUpdateStatus events, want at least 6", len(statuses))
	}
	if statuses[0].Updating != true || statuses[1].Updating != false || !statuses[1].Skipped {
		t.Fatalf("unchanged update sequence = %+v, want updating->skipped", statuses[:2])
	}
	if statuses[2].Updating != true || statuses[3].Updating != false || statuses[3].Skipped {
		t.Fatalf("changed update sequence = %+v, want updating->updated", statuses[2:4])
	}
	if statuses[4].Updating != true || statuses[5].Error != wantErr.Error() {
		t.Fatalf("error update sequence = %+v, want updating->error", statuses[4:6])
	}

	if got := proxyProviderSubscriptionInfo(nil); got != nil {
		t.Fatalf("proxyProviderSubscriptionInfo(nil) = %+v, want nil", got)
	}
}

func TestStopListenersAndEmptyLoadConfigAndTestURL(t *testing.T) {
	t.Cleanup(func() {
		clearTunnelSnapshots()
		isRunning.Store(false)
		isInit.Store(false)
		currentConfig = nil
		setTestURL("")
	})

	isRunning.Store(true)
	if !handleStopListener() {
		t.Fatal("handleStopListener returned false")
	}
	if isRunning.Load() {
		t.Fatal("isRunning still true after handleStopListener")
	}

	isInit.Store(true)
	isRunning.Store(true)
	if !handleShutdown() {
		t.Fatal("handleShutdown returned false")
	}
	if isInit.Load() || isRunning.Load() || currentConfig != nil {
		t.Fatal("handleShutdown left initialized/running state behind")
	}

	emptyFile := filepath.Join(t.TempDir(), "config.yaml")
	if err := os.WriteFile(emptyFile, []byte("   \n"), 0o600); err != nil {
		t.Fatalf("write empty config: %v", err)
	}
	cfg, err := loadConfig(emptyFile)
	if err != nil || cfg == nil {
		t.Fatalf("loadConfig(empty) = (%v, %v), want non-nil config", cfg, err)
	}

	raw := &config.RawConfig{
		ProxyGroup: []map[string]any{
			{"name": "sel", "type": "select"},
			{"name": "auto-default", "type": "url-test"},
			{"name": "auto-custom", "type": "url-test", "url": "https://custom.test/204"},
			{"name": "auto-provider", "type": "url-test", "use": []string{"sub"}},
		},
	}
	customURL := "https://override.example/generate_204"
	applyDefaultTestURLToRawConfig(raw, customURL)
	if _, hasURL := raw.ProxyGroup[0]["url"]; hasURL {
		t.Fatal("select group received a test url")
	}
	if raw.ProxyGroup[1]["url"] != customURL {
		t.Fatalf("auto-default url = %v, want %s", raw.ProxyGroup[1]["url"], customURL)
	}
	if raw.ProxyGroup[2]["url"] != "https://custom.test/204" {
		t.Fatalf("auto-custom url = %v, want preserved custom URL", raw.ProxyGroup[2]["url"])
	}
	if _, hasURL := raw.ProxyGroup[3]["url"]; hasURL {
		t.Fatal("provider-backed group had url overwritten")
	}
	if constant.DefaultTestURL == customURL {
		t.Fatal("constant.DefaultTestURL was mutated")
	}
}
