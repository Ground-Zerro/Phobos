/* SPDX-License-Identifier: MIT
 *
 * Phobos
 */

package phobos

import (
	"bufio"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
)

var (
	ErrSocks5Refused = errors.New("phobos: SOCKS5 server refused the request")
	errAuthFailed    = errors.New("phobos: SOCKS5 authentication failed")
)

type Socks5Config struct {
	Target     netip.AddrPort
	Key        []byte
	Masking    Masking
	Media      MediaParams
	Login      string
	Password   string
	ListenPort uint16
	Control    SocketControl
	Logf       func(format string, args ...any)
}

type Socks5Client struct {
	config   Socks5Config
	dialer   net.Dialer
	listener net.Listener

	running atomic.Bool
	wait    sync.WaitGroup

	mu    sync.Mutex
	serve map[net.Conn]struct{}
}

func NewSocks5Client(config Socks5Config) *Socks5Client {
	if config.Logf == nil {
		config.Logf = func(string, ...any) {}
	}
	return &Socks5Client{
		config: config,
		dialer: net.Dialer{Control: config.Control},
		serve:  make(map[net.Conn]struct{}),
	}
}

func (c *Socks5Client) trackServed(conn net.Conn) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.running.Load() {
		return false
	}
	c.serve[conn] = struct{}{}
	return true
}

func (c *Socks5Client) forgetServed(conn net.Conn) {
	c.mu.Lock()
	delete(c.serve, conn)
	c.mu.Unlock()
}

func (c *Socks5Client) closeServed() {
	c.mu.Lock()
	served := make([]net.Conn, 0, len(c.serve))
	for conn := range c.serve {
		served = append(served, conn)
	}
	c.serve = make(map[net.Conn]struct{})
	c.mu.Unlock()
	for _, conn := range served {
		conn.Close()
	}
}

func (c *Socks5Client) hasCredentials() bool {
	return len(c.config.Login) > 0 && len(c.config.Password) > 0
}

func (c *Socks5Client) open(ctx context.Context) (*obfConn, error) {
	if len(c.config.Key) == 0 {
		return nil, errors.New("phobos: obfuscation key is empty")
	}
	if !c.config.Target.IsValid() {
		return nil, errors.New("phobos: obfuscator target is not resolved")
	}
	conn, err := c.dialer.DialContext(ctx, "tcp", c.config.Target.String())
	if err != nil {
		return nil, err
	}
	if tcp, ok := conn.(*net.TCPConn); ok {
		tcp.SetNoDelay(true)
	}
	obfuscated := newObfConn(conn, c.config.Key, c.config.Masking, c.config.Media)
	if err := c.negotiate(obfuscated); err != nil {
		conn.Close()
		return nil, err
	}
	return obfuscated, nil
}

func (c *Socks5Client) negotiate(conn *obfConn) error {
	methods := []byte{methodNoAuth}
	if c.hasCredentials() {
		methods = []byte{methodNoAuth, methodUserPass}
	}
	if _, err := conn.Write(buildGreeting(methods...)); err != nil {
		return err
	}

	var response [2]byte
	if _, err := io.ReadFull(conn, response[:]); err != nil {
		return err
	}
	if response[0] != socks5Version {
		return errNotSocks5
	}
	switch response[1] {
	case methodNoAuth:
		return nil
	case methodUserPass:
		if !c.hasCredentials() {
			return errAuthFailed
		}
		auth, err := buildUserPass(c.config.Login, c.config.Password)
		if err != nil {
			return err
		}
		if _, err := conn.Write(auth); err != nil {
			return err
		}
		if _, err := io.ReadFull(conn, response[:]); err != nil {
			return err
		}
		if response[1] != 0x00 {
			return errAuthFailed
		}
		return nil
	default:
		return errAuthFailed
	}
}

func (c *Socks5Client) request(ctx context.Context, command byte, target socks5Target) (*obfConn, socks5Target, error) {
	conn, err := c.open(ctx)
	if err != nil {
		return nil, socks5Target{}, err
	}
	if _, err := conn.Write(buildRequest(command, target)); err != nil {
		conn.Close()
		return nil, socks5Target{}, err
	}
	buf := make([]byte, 262)
	reply, bound, err := readReply(conn, buf)
	if err != nil {
		conn.Close()
		return nil, socks5Target{}, err
	}
	if reply != replySucceeded {
		conn.Close()
		return nil, socks5Target{}, fmt.Errorf("%w: code %d", ErrSocks5Refused, reply)
	}
	return conn, bound, nil
}

func (c *Socks5Client) DialTCP(ctx context.Context, host string, port uint16) (net.Conn, error) {
	conn, _, err := c.request(ctx, cmdConnect, targetFromHostPort(host, port))
	if err != nil {
		return nil, err
	}
	return conn, nil
}

type Socks5UDPSession struct {
	conn   *obfConn
	reader *bufio.Reader

	writeMu sync.Mutex
	frame   []byte
}

func (c *Socks5Client) DialUDP(ctx context.Context) (*Socks5UDPSession, error) {
	conn, _, err := c.request(ctx, cmdUDPAssociate, socks5Target{atyp: atypIPv4, addr: make([]byte, 4)})
	if err != nil {
		return nil, err
	}
	return &Socks5UDPSession{
		conn:   conn,
		reader: bufio.NewReaderSize(conn, s5BufferSize),
		frame:  make([]byte, s5AccMax),
	}, nil
}

func (s *Socks5UDPSession) WriteTo(payload []byte, target netip.AddrPort) error {
	s.writeMu.Lock()
	defer s.writeMu.Unlock()
	frame, err := buildUDPFrame(targetFromAddrPort(target), payload, s.frame)
	if err != nil {
		return err
	}
	s.frame = frame[:0]
	_, err = s.conn.Write(frame)
	return err
}

func (s *Socks5UDPSession) ReadFrom(buf []byte) (int, netip.AddrPort, error) {
	var header [2]byte
	if _, err := io.ReadFull(s.reader, header[:]); err != nil {
		return 0, netip.AddrPort{}, err
	}
	length := int(binary.BigEndian.Uint16(header[:]))
	if length < 4 || length > s5AccMax {
		return 0, netip.AddrPort{}, errFrameCorrupt
	}
	frame := make([]byte, length)
	if _, err := io.ReadFull(s.reader, frame); err != nil {
		return 0, netip.AddrPort{}, err
	}
	target, offset, err := parseUDPHeader(frame)
	if err != nil {
		return 0, netip.AddrPort{}, err
	}
	source, ok := target.addrPort()
	if !ok {
		return 0, netip.AddrPort{}, errUnsupportedATYP
	}
	return copy(buf, frame[offset:]), source, nil
}

func (s *Socks5UDPSession) Close() error {
	return s.conn.Close()
}

func (c *Socks5Client) ListenPort() uint16 {
	if c.listener == nil {
		return 0
	}
	return uint16(c.listener.Addr().(*net.TCPAddr).Port)
}

func (c *Socks5Client) Start() error {
	if c.config.ListenPort == 0 {
		return nil
	}
	listener, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1), Port: int(c.config.ListenPort)})
	if err != nil {
		return fmt.Errorf("unable to open the local SOCKS5 listener: %w", err)
	}
	c.listener = listener
	c.running.Store(true)
	c.wait.Add(1)
	go c.acceptLoop()
	c.config.Logf("SOCKS5 proxy listening on 127.0.0.1:%d -> %v (masking %v)", c.ListenPort(), c.config.Target, c.config.Masking)
	return nil
}

func (c *Socks5Client) Stop() {
	if !c.running.Swap(false) {
		return
	}
	c.listener.Close()
	c.closeServed()
	c.wait.Wait()
	c.config.Logf("SOCKS5 proxy stopped")
}

func (c *Socks5Client) acceptLoop() {
	defer c.wait.Done()
	for {
		conn, err := c.listener.Accept()
		if err != nil {
			return
		}
		if !c.trackServed(conn) {
			conn.Close()
			return
		}
		c.wait.Add(1)
		go func() {
			defer c.wait.Done()
			defer c.forgetServed(conn)
			defer conn.Close()
			if err := c.handle(conn); err != nil && c.running.Load() {
				c.config.Logf("SOCKS5 proxy: %v", err)
			}
		}()
	}
}

func (c *Socks5Client) handle(conn net.Conn) error {
	reader := bufio.NewReader(conn)
	if err := c.serveHandshake(conn, reader); err != nil {
		return err
	}

	header := make([]byte, 262)
	if _, err := io.ReadFull(reader, header[:4]); err != nil {
		return err
	}
	if header[0] != socks5Version {
		return errNotSocks5
	}
	command := header[1]
	target, err := readTarget(reader, header[3:])
	if err != nil {
		return err
	}

	switch command {
	case cmdConnect:
		return c.serveConnect(conn, reader, target)
	case cmdUDPAssociate:
		return c.serveUDPAssociate(conn, reader)
	default:
		conn.Write(buildReply(replyCommandNotSupported, netip.AddrPort{}))
		return fmt.Errorf("phobos: unsupported SOCKS5 command %d", command)
	}
}

func (c *Socks5Client) serveHandshake(conn net.Conn, reader *bufio.Reader) error {
	var greeting [2]byte
	if _, err := io.ReadFull(reader, greeting[:]); err != nil {
		return err
	}
	if greeting[0] != socks5Version {
		return errNotSocks5
	}
	methods := make([]byte, greeting[1])
	if _, err := io.ReadFull(reader, methods); err != nil {
		return err
	}

	required := byte(methodNoAuth)
	if c.hasCredentials() {
		required = methodUserPass
	}
	offered := false
	for _, method := range methods {
		if method == required {
			offered = true
		}
	}
	if !offered {
		conn.Write([]byte{socks5Version, methodNone})
		return errAuthFailed
	}
	if _, err := conn.Write([]byte{socks5Version, required}); err != nil {
		return err
	}
	if required == methodNoAuth {
		return nil
	}
	return c.serveUserPass(conn, reader)
}

func (c *Socks5Client) serveUserPass(conn net.Conn, reader *bufio.Reader) error {
	var head [2]byte
	if _, err := io.ReadFull(reader, head[:]); err != nil {
		return err
	}
	if head[0] != userPassVersion {
		return errNotSocks5
	}
	login := make([]byte, head[1])
	if _, err := io.ReadFull(reader, login); err != nil {
		return err
	}
	var passwordLength [1]byte
	if _, err := io.ReadFull(reader, passwordLength[:]); err != nil {
		return err
	}
	password := make([]byte, passwordLength[0])
	if _, err := io.ReadFull(reader, password); err != nil {
		return err
	}

	if string(login) != c.config.Login || string(password) != c.config.Password {
		conn.Write([]byte{userPassVersion, 0x01})
		return errAuthFailed
	}
	_, err := conn.Write([]byte{userPassVersion, 0x00})
	return err
}

func readTarget(reader *bufio.Reader, buf []byte) (socks5Target, error) {
	switch buf[0] {
	case atypIPv4:
		if _, err := io.ReadFull(reader, buf[1:1+4+2]); err != nil {
			return socks5Target{}, err
		}
		target, _, err := parseTarget(buf[:1+4+2])
		return target, err
	case atypIPv6:
		if _, err := io.ReadFull(reader, buf[1:1+16+2]); err != nil {
			return socks5Target{}, err
		}
		target, _, err := parseTarget(buf[:1+16+2])
		return target, err
	case atypDomain:
		if _, err := io.ReadFull(reader, buf[1:2]); err != nil {
			return socks5Target{}, err
		}
		length := int(buf[1])
		if _, err := io.ReadFull(reader, buf[2:2+length+2]); err != nil {
			return socks5Target{}, err
		}
		target, _, err := parseTarget(buf[:2+length+2])
		return target, err
	default:
		return socks5Target{}, errUnsupportedATYP
	}
}

func (c *Socks5Client) serveConnect(conn net.Conn, reader *bufio.Reader, target socks5Target) error {
	upstream, _, err := c.request(context.Background(), cmdConnect, target)
	if err != nil {
		conn.Write(buildReply(replyGeneralFailure, netip.AddrPort{}))
		return err
	}
	defer upstream.Close()

	if _, err := conn.Write(buildReply(replySucceeded, netip.AddrPort{})); err != nil {
		return err
	}
	relay(conn, reader, upstream)
	return nil
}

func relay(downstream net.Conn, buffered *bufio.Reader, upstream net.Conn) {
	var wait sync.WaitGroup
	wait.Add(2)
	go func() {
		defer wait.Done()
		io.Copy(upstream, buffered)
		upstream.Close()
	}()
	go func() {
		defer wait.Done()
		io.Copy(downstream, upstream)
		downstream.Close()
	}()
	wait.Wait()
}

func (c *Socks5Client) serveUDPAssociate(conn net.Conn, reader *bufio.Reader) error {
	session, err := c.DialUDP(context.Background())
	if err != nil {
		conn.Write(buildReply(replyGeneralFailure, netip.AddrPort{}))
		return err
	}
	defer session.Close()

	relaySocket, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		conn.Write(buildReply(replyGeneralFailure, netip.AddrPort{}))
		return err
	}
	defer relaySocket.Close()

	bound := relaySocket.LocalAddr().(*net.UDPAddr).AddrPort()
	if _, err := conn.Write(buildReply(replySucceeded, bound)); err != nil {
		return err
	}

	var client atomic.Pointer[netip.AddrPort]
	var wait sync.WaitGroup
	wait.Add(2)
	go func() {
		defer wait.Done()
		defer session.Close()
		buf := make([]byte, s5AccMax)
		for {
			n, source, err := relaySocket.ReadFromUDPAddrPort(buf)
			if err != nil {
				return
			}
			target, offset, err := parseUDPHeader(buf[:n])
			if err != nil {
				continue
			}
			destination, ok := target.addrPort()
			if !ok {
				continue
			}
			client.Store(&source)
			if err := session.WriteTo(buf[offset:n], destination); err != nil {
				return
			}
		}
	}()
	go func() {
		defer wait.Done()
		defer relaySocket.Close()
		payload := make([]byte, s5AccMax)
		out := make([]byte, s5AccMax)
		for {
			n, source, err := session.ReadFrom(payload)
			if err != nil {
				return
			}
			destination := client.Load()
			if destination == nil {
				continue
			}
			frame, err := buildUDPFrame(targetFromAddrPort(source), payload[:n], out)
			if err != nil {
				continue
			}
			if _, err := relaySocket.WriteToUDPAddrPort(frame[2:], *destination); err != nil {
				return
			}
		}
	}()

	io.Copy(io.Discard, reader)
	relaySocket.Close()
	session.Close()
	wait.Wait()
	return nil
}
