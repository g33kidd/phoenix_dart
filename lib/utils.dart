import 'dart:convert';

const String VSN = "2.0.0";
class SOCKET_STATES {
  static const int connecting = 0;
  static const int open = 1;
  static const int closing = 2;
  static const int closed = 3;
}
const int DEFAULT_TIMEOUT = 10000;
const int WS_CLOSE_NORMAL = 1000;

class CHANNEL_STATES {
  static const String closed = "closed";
  static const String errored = "errored";  
  static const String joined = "joined";
  static const String joining = "joining";
  static const String leaving = "leaving";
}
class CHANNEL_EVENTS {
  static const String close = "phx_close";
  static const String error = "phx_error";
  static const String join = "phx_join";
  static const String reply = "phx_reply";
  static const String leave = "phx_leave";
}

List<String> CHANNEL_LIFECYCLE_EVENTS = [
  CHANNEL_EVENTS.close,
  CHANNEL_EVENTS.error,
  CHANNEL_EVENTS.join,
  CHANNEL_EVENTS.reply,
  CHANNEL_EVENTS.leave
];
class TRANSPORTS {
  static const String longpoll = "longpoll";
  static const String websocket = "websocket";
}


class Serializer {
  static encode(Map msg, callback){
    List payload = [
      msg["join_ref"], msg["ref"], msg["topic"], msg["event"], msg["payload"]
    ];
    return callback(JSON.encode(payload));
  }

  static decode(rawPayload, callback){
    List e = JSON.decode(rawPayload);
    return callback({"join_ref": e[0], "ref": e[1], "topic": e[2], "event": e[3], "payload": e[4]});
  }
}

/*
class Presence {

  static syncState(currentState, newState, onJoin, onLeave){
    var state = Presence.clone(currentState);
    var joins = {};
    var leaves = {};

    Presence.map(state, (key, presence) {
      if(!newState[key]){
        leaves[key] = presence;
      }
    });
    Presence.map(newState, (key, newPresence) {
      var currentPresence = state[key];
      if (currentPresence){
        var newRefs = newPresence.metas.map((m) => m.phx_ref);
        var curRefs = currentPresence.metas.map((m) => m.phx_ref);
        var joinedMetas = newPresence.metas.filter((m) => curRefs.indexOf(m.phx_ref) < 0);
        var leftMetas = currentPresence.metas.filter((m) => newRefs.indexOf(m.phx_ref) < 0);
        if(joinedMetas.length > 0){
          joins[key] = newPresence;
          joins[key].metas = joinedMetas;
        }
        if(leftMetas.length > 0){
          leaves[key] = Presence.clone(currentPresence);
          leaves[key].metas = leftMetas;
        }
      } else {
        joins[key] = newPresence;
      }
    });
    return Presence.syncDiff(state, {"joins": joins, "leaves": leaves}, onJoin, onLeave);
  }

  static syncDiff(currentState, Map joinLeaves, onJoin, onLeave){
    var joins = joinLeaves["joins"];
    var leaves = joinLeaves["leaves"];
    var state = Presence.clone(currentState);
    if (!onJoin){ onJoin = (){}; }
    if (!onLeave){ onLeave = (){}; }

    Presence.map(joins, (key, newPresence) {
      var currentPresence = state[key];
      state[key] = newPresence;
      if(currentPresence){
        state[key].metas.unshift(...currentPresence.metas);
      }
      onJoin(key, currentPresence, newPresence);
    });
    Presence.map(leaves, (key, leftPresence) {
      var currentPresence = state[key];
      if (currentPresence){
        var refsToRemove = leftPresence.metas.map((m) => m.phx_ref);
        currentPresence.metas = currentPresence.metas.filter((p) {
          return refsToRemove.indexOf(p.phx_ref) < 0;
        });
        onLeave(key, currentPresence, leftPresence);
        if(currentPresence.metas.length == 0){
          delete state[key];
        }
      }
    });
    return state;
  }

  static list(presences, chooser){
    if(!chooser){ chooser = (key, pres){ return pres; }; }

    return Presence.map((presences, ele) { return chooser(ele.key, ele.presence); });
  }

  // private

  static map(obj, func){
    return Object.getOwnPropertyNames(obj).map((key) => func(key, obj[key]));
  }

  static clone(obj){ return JSON.decode(JSON.encode(obj)); }
}
*/