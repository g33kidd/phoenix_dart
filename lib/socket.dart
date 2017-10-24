import 'dart:async';
import 'dart:io';
import './utils.dart';
import './timer.dart';
import './ajax.dart';
import 'channel.dart';

class Socket {

  Map<String, List> stateChangeCallbacks;
  List<Channel> channels;
  List sendBuffer;
  var ref;
  var timeout;  
  var defaultDecoder;
  var defaultEncoder;
  var encode;
  var decode;
  var heartbeatIntervalMs;
  var reconnectAfterMs;
  var logger;
  Map params;
  String endPoint;
  PhoenixTimer heartbeatTimer;
  var pendingHeartbeatRef;
  PhoenixTimer reconnectTimer;
  WebSocket conn;

  Socket(String endPoint, { timeout, heartbeatIntervalMs = 30000, reconnectAfterMs, logger, Map params}){
    this.stateChangeCallbacks = {"open": [], "close": [], "error": [], "message": []};
    this.channels             = [];
    this.sendBuffer           = [];
    this.ref                  = 0;
    this.timeout              = timeout ?? DEFAULT_TIMEOUT;  
    this.defaultEncoder       = Serializer.encode;
    this.defaultDecoder       = Serializer.decode;
    this.encode = encode ?? this.defaultEncoder;
    this.decode = decode ?? this.defaultDecoder;
    this.heartbeatIntervalMs  = heartbeatIntervalMs;
    this.reconnectAfterMs     = reconnectAfterMs ?? (tries){
      return [1000, 2000, 5000, 10000][tries - 1] ?? 10000;
    };
    this.logger               = logger ?? (){}; // noop
    this.params               = params ?? new Map();
    this.endPoint             = "${endPoint}/${TRANSPORTS.websocket}";
    this.heartbeatTimer       = null;
    this.pendingHeartbeatRef  = null;
    this.reconnectTimer       = new PhoenixTimer(() {
      this.disconnect(() => this.connect());
    }, this.reconnectAfterMs);
  }

  String protocol(){ return endPoint.contains("https") ? "wss" : "ws"; }

  String endPointURL(){
    String uri = Ajax.appendParams(
      Ajax.appendParams(this.endPoint, this.params), {"vsn": VSN});
    if(uri[0] != "/"){ return uri; }
    if(uri[1] == "/"){ return "${this.protocol()}:${uri}"; }
    return "";
    //return "${this.protocol()}://${location.host}${uri}";
  }

  void disconnect(callback, [code, reason]){
    print("socket disconnect");
    if(this.conn != null){
      if(code != null){ this.conn.close(code, reason ?? ""); } else { this.conn.close(); }
      this.conn = null;
    }
    if (callback != null) callback();
  }

  Future connect([Map params]) async{
    print("socket connect");
    if(params != null){
      print("passing params to connect is deprecated. Instead pass :params to the Socket constructor");
      this.params = params;
    }
    if(this.conn == null){
      try {
        this.conn = await WebSocket.connect(this.endPointURL());
        this.onConnOpen();
        this.conn.listen(


                (event) =>  this.onConnMessage(event),
            onError: (error) => this.onError(error),
          onDone: () => print("connection done")
        );
      } catch (exception) {
        this.onConnError(exception);
      }
      //this.conn.onclose   = (event) => this.onConnClose(event);
    }
  }

  void log(kind, msg, [data]){ this.logger(kind, msg, data); }

  // Registers callbacks for connection state change events
  //
  // Examples
  //
  //    socket.onError(function(error){ alert("An error occurred") })
  //
  void onOpen     (callback){ this.stateChangeCallbacks["open"].add(callback); }
  void onClose    (callback){ this.stateChangeCallbacks["close"].add(callback); }
  void onError    (callback){ this.stateChangeCallbacks["error"].add(callback); }
  void onMessage  (callback){ this.stateChangeCallbacks["message"].add(callback); }

  void onConnOpen(){
    this.log("transport", "connected to ${this.endPointURL()}");
    this.flushSendBuffer();

    this.reconnectTimer.reset();


    /*
    if(!this.conn.skipHeartbeat){
      this.heartbeatTimer.reset();
      this.heartbeatTimer = new PhoenixTimer(() => this.sendHeartbeat(), this.heartbeatIntervalMs);
    }*/

    this.stateChangeCallbacks["open"].forEach( (callback) => callback() );
    print("socket onConnOpen End");
  }

  void onConnClose(event){
    this.log("transport", "close", event);
    this.triggerChanError();
    this.heartbeatTimer.reset();
    this.reconnectTimer.scheduleTimeout();
    this.stateChangeCallbacks["close"].forEach( (callback) => callback(event));
  }

  void onConnError(error){
    this.log("transport", error);
    this.triggerChanError();
    this.stateChangeCallbacks["error"].forEach((callback) => callback(error) );
  }

  void triggerChanError(){
    this.channels.forEach( (Channel channel) => channel.trigger(CHANNEL_EVENTS.error) );
  }

  String connectionState(){
    if(this.conn == null) return "closed";
    switch(this.conn.readyState) {
      case SOCKET_STATES.connecting:
        return "connecting";
      case SOCKET_STATES.open:
        return "open";
      case SOCKET_STATES.closing:
        return "closing";
      default:
        return "closed";
    }
  }

  isConnected(){ return this.connectionState() == "open"; }

  remove(channel){
    print("socket remove");
    this.channels = this.channels.where((c) => c.joinRef() != channel.joinRef()).toList();
  }

  channel(topic, [chanParams]){
    chanParams ??= {};
    var chan = new Channel(topic, chanParams, this);
    this.channels.add(chan);
    return chan;
  }

  void push(Map data){
    var callback = () {
      print("socket push callback $data");
      this.encode(data, (result) {
        print("socket push 1 $result");
        //this.conn.send(result);
        this.log("push", "result $result");
        this.conn.add(result);
      });
    };
    this.log("push", "${data['topic']} ${data['event']} (${data['join_ref']}, ${data['ref']})", data['payload']);
    if(this.isConnected()){
      this.log("push", "is connected");
      callback();
    }
    else {
      this.log("push", "is not connected");
      this.sendBuffer.add(callback);
    }
  }

  makeRef(){
    var newRef = this.ref + 1;
    if(newRef == this.ref){ this.ref = 0; } else { this.ref = newRef; }

    return this.ref.toString();
  }

  sendHeartbeat(){ 
    if(this.isConnected()){ 
      if(this.pendingHeartbeatRef){
        this.pendingHeartbeatRef = null;
        this.log("transport", "heartbeat timeout. Attempting to re-establish connection");
        this.conn.close(WS_CLOSE_NORMAL, "hearbeat timeout");        
      } else {
        this.pendingHeartbeatRef = this.makeRef();
        this.push({"topic": "phoenix", "event": "heartbeat", "payload": {}, "ref": this.pendingHeartbeatRef});
      }
    }
  }

  flushSendBuffer(){
    if(this.isConnected() && this.sendBuffer.length > 0){
      this.sendBuffer.forEach( (callback) => callback() );
      this.sendBuffer = [];
    }
  }

  onConnMessage(rawMessage){
    print("onConnMessage $rawMessage");
    this.decode(rawMessage, (Map msg) {
      var topic = msg["topic"];
      var event = msg["event"];
      Map payload = msg["payload"];
      var ref = msg["ref"];
      var joinRef = msg.containsKey("join_ref") ? msg["join_ref"] : "";
      
      if(ref != null && ref == this.pendingHeartbeatRef){ this.pendingHeartbeatRef = null; }
      String status = payload["status"] ?? "";
      String refLog = "($ref)";
      this.log("receive", "$status $topic $event $refLog", payload);
      this.channels.where( (channel) => channel.isMember(topic, event, payload, joinRef) ).toList()
                   .forEach( (channel) => channel.trigger(event, payload, ref, joinRef) );
      this.stateChangeCallbacks["message"].forEach( (callback) => callback(msg) );
    });
  }
}
