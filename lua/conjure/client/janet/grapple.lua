-- [nfnl] Compiled from fnl/conjure/client/janet/grapple.fnl by https://github.com/Olical/nfnl, do not edit.
local _local_1_ = require("nfnl.module")
local autoload = _local_1_["autoload"]
local a = autoload("conjure.aniseed.core")
local client = autoload("conjure.client")
local config = autoload("conjure.config")
local log = autoload("conjure.log")
local mapping = autoload("conjure.mapping")
local remote = autoload("conjure.remote.mrepl")
local s = autoload("nfnl.string")
local text = autoload("conjure.text")
local ts = autoload("conjure.tree-sitter")
local buf_suffix = ".janet"
local comment_prefix = "# "
local comment_node_3f = ts["lisp-comment-node?"]
local form_node_3f = ts["node-surrounded-by-form-pair-chars?"]
config.merge({client = {janet = {mrepl = {connection = {default_host = "127.0.0.1", default_port = "3737"}}}}})
if config["get-in"]({"mapping", "enable_defaults"}) then
  config.merge({client = {janet = {mrepl = {mapping = {connect = "cc", disconnect = "cd"}}}}})
else
end
local state
local function _3_()
  return {conn = nil}
end
state = client["new-state"](_3_)
local function upcase(s0, n)
  local start = string.sub(s0, 1, n)
  local rest = string.sub(s0, (n + 1))
  return (string.upper(start) .. rest)
end
local function error_msg_3f(msg)
  return ("err" == msg.tag)
end
local function display_error(msg)
  return log.append({("# " .. msg.msg)})
end
local function handle_sess_new(resp)
  a.assoc(state("conn"), "session", resp.sess)
  local impl_name = resp["janet/impl"][1]
  local impl_ver = resp["janet/impl"][2]
  local serv_name = resp["janet/serv"][1]
  local serv_ver = resp["janet/serv"][2]
  return log.append({("# Connected to " .. upcase(serv_name, 1) .. " v" .. serv_ver .. " running " .. upcase(impl_name, 1) .. " v" .. impl_ver .. " as session " .. resp.sess)})
end
local function handle_env_eval(resp)
  if ("out" == resp.tag) then
    return log.append({("# (out) " .. resp.val)})
  elseif ("err" == resp.tag) then
    return log.append({("# (err) " .. resp.value)})
  else
    return log.append({resp.val})
  end
end
local function handle_message(msg)
  if msg then
    if error_msg_3f(msg) then
      return display_error(msg)
    elseif ("sess.new" == msg.op) then
      return handle_sess_new(msg)
    elseif ("env.eval" == msg.op) then
      return handle_env_eval(msg)
    else
      return log.append({"# Unrecognised message"})
    end
  else
    return nil
  end
end
local function with_conn_or_warn(f, opts)
  local conn = state("conn")
  if conn then
    return f(conn)
  else
    return log.append({"# No connection"})
  end
end
local function connected_3f()
  if state("conn") then
    return true
  else
    return false
  end
end
local function display_conn_status(status)
  local function _9_(conn)
    return log.append({("# " .. conn.host .. ":" .. conn.port .. " (" .. status .. ")")}, {["break?"] = true})
  end
  return with_conn_or_warn(_9_)
end
local function disconnect()
  local function _10_(conn)
    conn.destroy()
    display_conn_status("disconnected")
    return a.assoc(state(), "conn", nil)
  end
  return with_conn_or_warn(_10_)
end
local function connect(opts)
  local opts0 = (opts or {})
  local host = (opts0.host or config["get-in"]({"client", "janet", "mrepl", "connection", "default_host"}))
  local port = (opts0.port or config["get-in"]({"client", "janet", "mrepl", "connection", "default_port"}))
  if state("conn") then
    disconnect()
  else
  end
  local conn
  local function _12_(err)
    display_conn_status(err)
    return disconnect()
  end
  local function _13_()
    a.assoc(state(), "conn", conn)
    return display_conn_status("connected")
  end
  local function _14_(err)
    if err then
      return display_conn_status(err)
    else
      return disconnect()
    end
  end
  conn = remote.connect({host = host, port = port, lang = "net.inqk/janet/1.0", ["on-message"] = handle_message, ["on-failure"] = _12_, ["on-success"] = _13_, ["on-error"] = _14_})
  return nil
end
local function try_ensure_conn()
  if not connected_3f() then
    return connect({["silent?"] = true})
  else
    return nil
  end
end
local function eval_str(opts)
  try_ensure_conn()
  local conn = state("conn")
  return conn.send({op = "env.eval", code = opts.code, ns = opts["file-path"], ["janet/col"] = a["get-in"](opts.range, {"start", 2}, 1), ["janet/line"] = a["get-in"](opts.range, {"start", 1}, 1)})
end
local function doc_str(opts)
  try_ensure_conn()
  local function _17_(_241)
    return ("(doc " .. _241 .. ")")
  end
  return eval_str(a.update(opts, "code", _17_))
end
local function eval_file(opts)
  try_ensure_conn()
  return eval_str(a.assoc(opts, "code", ("(do (dofile \"" .. opts["file-path"] .. "\" :env (fiber/getenv (fiber/current))) nil)")))
end
local function on_filetype()
  mapping.buf("JanetDisconnect", config["get-in"]({"client", "janet", "mrepl", "mapping", "disconnect"}), disconnect, {desc = "Disconnect from the REPL"})
  local function _18_()
    return connect()
  end
  return mapping.buf("JanetConnect", config["get-in"]({"client", "janet", "mrepl", "mapping", "connect"}), _18_, {desc = "Connect to a REPL"})
end
local function on_load()
  return connect({})
end
local function on_exit()
  return disconnect()
end
return {["buf-suffix"] = buf_suffix, ["comment-node?"] = comment_node_3f, ["comment-prefix"] = comment_prefix, connect = connect, disconnect = disconnect, ["doc-str"] = doc_str, ["eval-file"] = eval_file, ["eval-str"] = eval_str, ["form-node?"] = form_node_3f, ["on-exit"] = on_exit, ["on-filetype"] = on_filetype, ["on-load"] = on_load}
