// 브라우저끼리 직접 연결(WebRTC)하는 멀티플레이 연결부. PeerJS 공개 중계 서버는 처음 서로를 찾을 때만 쓴다.
// Godot에서는 JavaScriptBridge로 GNet.host/join/send/poll을 호출한다.
(function () {
  var PREFIX = 'ghostschool-v1-';
  var G = window.GNet = { peer: null, conns: {}, inbox: [], status: 'idle', myId: '', isHost: false, error: '' };
  function push(m) { G.inbox.push(m); }
  function setupConn(c) {
    c.on('open', function () {
      G.conns[c.peer] = c;
      if (!G.isHost) G.status = 'joined';
      push({ t: '_join', from: c.peer });
    });
    c.on('data', function (d) { push({ t: '_data', from: c.peer, d: d }); });
    c.on('close', function () { delete G.conns[c.peer]; push({ t: '_leave', from: c.peer }); });
    c.on('error', function (e) { push({ t: '_err', from: c.peer, e: String(e) }); });
  }
  G.reset = function () {
    try { if (G.peer) G.peer.destroy(); } catch (e) {}
    G.peer = null; G.conns = {}; G.inbox = []; G.status = 'idle'; G.error = ''; G.myId = '';
  };
  G.host = function (code) {
    G.reset(); G.isHost = true; G.status = 'connecting';
    if (!window.Peer) { G.status = 'error'; G.error = 'no-peerjs'; return; }
    G.peer = new Peer(PREFIX + code, { debug: 0 });
    G.peer.on('open', function (id) { G.myId = id; G.status = 'hosting'; });
    G.peer.on('connection', function (c) {
      if (Object.keys(G.conns).length >= 3) {  // 최대 4명
        c.on('open', function () { c.send({ t: 'full' }); setTimeout(function () { c.close(); }, 300); });
        return;
      }
      setupConn(c);
    });
    G.peer.on('error', function (e) { G.status = 'error'; G.error = (e && e.type) || String(e); });
    G.peer.on('disconnected', function () { try { G.peer.reconnect(); } catch (e) {} });
  };
  G.join = function (code) {
    G.reset(); G.isHost = false; G.status = 'connecting';
    if (!window.Peer) { G.status = 'error'; G.error = 'no-peerjs'; return; }
    G.peer = new Peer(undefined, { debug: 0 });
    G.peer.on('open', function (id) {
      G.myId = id;
      setupConn(G.peer.connect(PREFIX + code, { reliable: true, serialization: 'json' }));
      setTimeout(function () { if (G.status === 'connecting') { G.status = 'error'; G.error = 'timeout'; } }, 9000);
    });
    G.peer.on('error', function (e) { G.status = 'error'; G.error = (e && e.type) || String(e); });
  };
  G.send = function (to, msg) {
    if (to === '*') { for (var k in G.conns) { try { G.conns[k].send(msg); } catch (e) {} } }
    else if (G.conns[to]) { try { G.conns[to].send(msg); } catch (e) {} }
  };
  G.poll = function () {
    var s = JSON.stringify({ status: G.status, id: G.myId, err: G.error, msgs: G.inbox });
    G.inbox = [];
    return s;
  };
})();
