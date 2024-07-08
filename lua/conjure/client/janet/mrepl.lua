local _2afile_2a = "fnl/conjure/client/janet/mrepl.fnl"
local _2amodule_name_2a = "conjure.client.janet.mrepl"
local _2amodule_2a
do
  package.loaded[_2amodule_name_2a] = {}
  _2amodule_2a = package.loaded[_2amodule_name_2a]
end
local _2amodule_locals_2a
do
  _2amodule_2a["aniseed/locals"] = {}
  _2amodule_locals_2a = (_2amodule_2a)["aniseed/locals"]
end
local autoload = (require("conjure.aniseed.autoload")).autoload
local a, client, config, fs, log, mapping, nvim, stdio, str, ts, _ = autoload("conjure.aniseed.core"), autoload("conjure.client"), autoload("conjure.config"), autoload("conjure.fs"), autoload("conjure.log"), autoload("conjure.mapping"), autoload("conjure.aniseed.nvim"), autoload("conjure.remote.stdio"), autoload("conjure.aniseed.string"), autoload("conjure.tree-sitter"), nil
_2amodule_locals_2a["a"] = a
_2amodule_locals_2a["client"] = client
_2amodule_locals_2a["config"] = config
_2amodule_locals_2a["fs"] = fs
_2amodule_locals_2a["log"] = log
_2amodule_locals_2a["mapping"] = mapping
_2amodule_locals_2a["nvim"] = nvim
_2amodule_locals_2a["stdio"] = stdio
_2amodule_locals_2a["str"] = str
_2amodule_locals_2a["ts"] = ts
_2amodule_locals_2a["_"] = _
config.merge({client = {janet = {mrepl = {mapping = {start = "cs", stop = "cS"}, command = "janet -n -s", prompt_pattern = "repl:[0-9]+:[^>]*> "}}}})
local cfg = config["get-in-fn"]({"client", "janet", "mrepl"})
do end (_2amodule_locals_2a)["cfg"] = cfg
local state
local function _1_()
  return {repl = nil, ["project-root"] = nil, ["project-syspath"] = nil}
end
state = ((_2amodule_2a).state or client["new-state"](_1_))
do end (_2amodule_locals_2a)["state"] = state
local buf_suffix = ".janet"
_2amodule_2a["buf-suffix"] = buf_suffix
local comment_prefix = "# "
_2amodule_2a["comment-prefix"] = comment_prefix
local form_node_3f = ts["node-surrounded-by-form-pair-chars?"]
_2amodule_2a["form-node?"] = form_node_3f
local prelude = "(do\n  (def mb 255)\n\n  (var env nil)\n  (var path nil)\n  (var cnt 0)\n\n  (defn supervise\n    ```\n    Supervises the current evaluation\n\n    mrepl allows a client to send control instructions to the supervisor by\n    prepending a magic byte to the beginning of a new line. If a magic byte is\n    present, this function is used to parse the instruction.\n\n    Only one instruction is supported currently. This instruction changes the\n    source file and changes the evaluation environment, either using an\n    existing environment from the module cache or creating a new environment\n    (saving it to the module cache).\n    ```\n    [buf p]\n    (def msg (parse (buffer/slice buf 1)))\n    (def cmd (get msg :cmd))\n    (case (get msg :cmd)\n      :update/source\n      (do\n        (def {:path new-path :line line :col col} (get msg :payload))\n        (parser/where p line col)\n        (unless (= path new-path)\n          (parser/flush p)\n          (set env (or (get module/cache new-path)\n                       (do\n                         (def new-env (make-env))\n                         (put module/cache new-path new-env)\n                         new-env)))\n          (set path new-path))\n        [:source path])))\n\n  (defn chunks\n    ```\n    Gets chunk of input\n\n    When evaluating input in `run-context`, this function adds the input to the\n    buffer to process. If the input begins with a magic byte, the `supervise`\n    function is called.\n    ```\n    [buf p]\n    (def prmpt (string \"repl:\" (++ cnt) \":\" (:state p :delimiters) \"> \"))\n    (file/write stdout prmpt)\n    (file/flush stdout)\n    (file/read stdin :line buf)\n    (if (= mb (get buf 0))\n      (supervise buf p)\n      (do\n        (when (zero? (length buf))\n          (put env :exit true)\n          (put env :exit-value false)))))\n\n  (defn on-status\n    ```\n    Handles status signals\n\n    Evaluated input is run in a fiber by `run-context`. This function is used\n    to determine what to do based upon the signal of the fiber.\n    ```\n    [f x]\n    (def fs (fiber/status f))\n    (if (= :dead fs)\n      (do\n        (put env '_ @{:value x})\n        (def pf (get env *pretty-format* \"%q\"))\n        (try\n          (printf pf x)\n          ([e]\n            (eprintf \"bad pretty format %v: %v\" pf e)\n            (eflush)))\n        (flush))\n      (do\n        (debug/stacktrace f x \"\")\n        (eflush)\n        (if (get env :debug) (debugger f 1)))))\n\n  (def lint-levels\n    {:none 0\n     :relaxed 1\n     :normal 2\n     :strict 3\n     :all math/inf})\n\n  (defn run-context\n    ```\n    Runs code in a context\n\n    This function is an almost unmodified version of Janet's core `run-context`\n    function. The only changes are removing the `env` binding from the initial\n    def statement, removing the default setup for the `env` binding and\n    avoiding all uses of quotation marks.\n    ```\n    [opts]\n    (def {:chunks chunks\n          :on-status onstatus\n          :on-compile-error on-compile-error\n          :on-compile-warning on-compile-warning\n          :on-parse-error on-parse-error\n          :fiber-flags guard\n          :evaluator evaluator\n          :source default-where\n          :parser parser\n          :read read\n          :expander expand} opts)\n    (default chunks (fn chunks [buf p] (getline \"\" buf env)))\n    (default onstatus debug/stacktrace)\n    (default on-compile-error bad-compile)\n    (default on-compile-warning warn-compile)\n    (default on-parse-error bad-parse)\n    (default evaluator (fn evaluate [x &] (x)))\n    (default default-where :<anonymous>)\n    (default guard :ydt)\n\n    (var where default-where)\n\n    (if (string? where)\n      (put env *current-file* where))\n\n    # Evaluate 1 source form in a protected manner\n    (def lints @[])\n    (defn eval1 [source &opt l c]\n      (def source (if expand (expand source) source))\n      (var good true)\n      (var resumeval nil)\n      (def f\n        (fiber/new\n          (fn []\n            (array/clear lints)\n            (def res (compile source env where lints))\n            (unless (empty? lints)\n              # Convert lint levels to numbers.\n              (def levels (get env *lint-levels* lint-levels))\n              (def lint-error (get env *lint-error*))\n              (def lint-warning (get env *lint-warn*))\n              (def lint-error (or (get levels lint-error lint-error) 0))\n              (def lint-warning (or (get levels lint-warning lint-warning) 2))\n              (each [level line col msg] lints\n                (def lvl (get lint-levels level 0))\n                (cond\n                  (<= lvl lint-error) (do\n                                        (set good false)\n                                        (on-compile-error msg nil where (or line l) (or col c)))\n                  (<= lvl lint-warning) (on-compile-warning msg level where (or line l) (or col c)))))\n            (when good\n              (if (= (type res) :function)\n                (evaluator res source env where)\n                (do\n                  (set good false)\n                  (def {:error err :line line :column column :fiber errf} res)\n                  (on-compile-error err errf where (or line l) (or column c))))))\n          guard\n          env))\n      (while (fiber/can-resume? f)\n        (def res (resume f resumeval))\n        (when good (set resumeval (onstatus f res)))))\n\n    # Reader version\n    (when read\n      (forever\n        (if (in env :exit) (break))\n        (eval1 (read env where)))\n      (break (in env :exit-value env)))\n\n    # The parser object\n    (def p (or parser (parser/new)))\n    (def p-consume (p :consume))\n    (def p-produce (p :produce))\n    (def p-status (p :status))\n    (def p-has-more (p :has-more))\n\n    (defn parse-err\n      [p where]\n      (def f (coro (on-parse-error p where)))\n      (fiber/setenv f env)\n      (resume f))\n\n    (defn produce []\n      (def tup (p-produce p true))\n      [(in tup 0) ;(tuple/sourcemap tup)])\n\n    # Loop\n    (def buf @\"\")\n    (var parser-not-done true)\n    (while parser-not-done\n      (if (env :exit) (break))\n      (buffer/clear buf)\n      (match (chunks buf p)\n        :cancel\n        (do\n          # A :cancel chunk represents a cancelled form in the REPL, so reset.\n          (:flush p)\n          (buffer/clear buf))\n\n        [:source new-where]\n        (do\n          (set where new-where)\n          (if (string? new-where)\n            (put env *current-file* new-where)))\n\n        (do\n          (var pindex 0)\n          (var pstatus nil)\n          (def len (length buf))\n          (when (= len 0)\n            (:eof p)\n            (set parser-not-done false))\n          (while (> len pindex)\n            (+= pindex (p-consume p buf pindex))\n            (while (p-has-more p)\n              (eval1 ;(produce))\n              (if (env :exit) (break)))\n            (when (= (p-status p) :error)\n              (parse-err p where)\n              (if (env :exit) (break)))))))\n\n    # Check final parser state\n    (unless (env :exit)\n      (while (p-has-more p)\n        (eval1 ;(produce))\n        (if (env :exit) (break)))\n      (when (= (p-status p) :error)\n        (parse-err p where)))\n\n    (put env :exit nil)\n    (in env :exit-value env))\n\n  (defn repl\n    ```\n    Creates a REPL\n\n    This function creates a REPL that uses mrepl's `chunks` and `on-status`\n    functions.\n    ```\n    []\n    (set env (make-env))\n    (def p (parser/new))\n    (forever\n      (unless (run-context {:chunks chunks\n                            :on-status on-status\n                            :parser p})\n        (break))))\n\n  (put root-env :redef true)\n\n  (print \"[mrepl] Loaded prelude\")\n\n  (repl))\n"
_2amodule_2a["prelude"] = prelude
local function unbatch(msgs)
  local function _2_(_241)
    return (a.get(_241, "out") or a.get(_241, "err"))
  end
  return {out = str.join("", a.map(_2_, msgs))}
end
_2amodule_2a["unbatch"] = unbatch
local function format_message(msg)
  local function _3_(_241)
    return ("" ~= _241)
  end
  return a.filter(_3_, str.split(msg.out, "\n"))
end
_2amodule_locals_2a["format-message"] = format_message
local function send_to_repl(msg, opts)
  local repl = state("repl")
  if repl then
    local function _4_(msgs)
      local lines = format_message(unbatch(msgs))
      if opts["on-result"] then
        opts["on-result"](a.last(lines))
      else
      end
      return log.append(lines)
    end
    return repl.send(msg, _4_, {["batch?"] = true})
  else
    return log.append({(comment_prefix .. "No REPL running")})
  end
end
_2amodule_locals_2a["send-to-repl"] = send_to_repl
local function supervisor_msg(cmd, payload)
  return ("\255{:cmd " .. cmd .. " :payload " .. payload .. "}\n")
end
_2amodule_locals_2a["supervisor-msg"] = supervisor_msg
local function tell_supervisor(cmd, opts)
  local _8_
  do
    local _7_ = cmd
    if (_7_ == "update-source") then
      local path
      if state("project-path") then
        path = fs["resolve-relative-to"](opts["file-path"], state("project-path"))
      else
        path = opts["file-path"]
      end
      _8_ = supervisor_msg(":update/source", ("{:path `" .. path .. "` :line " .. a["get-in"](opts.range, {"start", 1}, 1) .. " :col " .. a["get-in"](opts.range, {"start", 2}, 0) .. "}"))
    else
      _8_ = nil
    end
  end
  return send_to_repl(_8_, {silent = true})
end
_2amodule_locals_2a["tell-supervisor"] = tell_supervisor
local function prep_code(s)
  return (s .. "\n")
end
_2amodule_locals_2a["prep-code"] = prep_code
local function eval_str(opts)
  tell_supervisor("update-source", opts)
  return send_to_repl(prep_code(opts.code), opts)
end
_2amodule_2a["eval-str"] = eval_str
local function eval_file(opts)
  return eval_str(a.assoc(opts, "code", a.slurp(opts["file-path"])))
end
_2amodule_2a["eval-file"] = eval_file
local function doc_str(opts)
  local function _13_(_241)
    return ("(doc " .. _241 .. ")")
  end
  a.update(opts, "code", _13_)
  return send_to_repl(prep_code(opts.code), opts)
end
_2amodule_2a["doc-str"] = doc_str
local function display_repl_status(status)
  local repl = state("repl")
  if repl then
    return log.append({(comment_prefix .. a["pr-str"](a["get-in"](repl, {"opts", "cmd"})) .. " (" .. status .. ")")}, {["break?"] = true})
  else
    return nil
  end
end
_2amodule_locals_2a["display-repl-status"] = display_repl_status
local function find_project_root()
  local pwd = nvim.fn.expand("%:p:h")
  local file_path = fs["upwards-file-search"]({"project.janet"}, pwd)
  if file_path then
    return fs["parent-dir"](nvim.fn.fnamemodify(file_path, ":p"))
  else
    return nil
  end
end
_2amodule_locals_2a["find-project-root"] = find_project_root
local function stop()
  local repl = state("repl")
  if repl then
    repl.destroy()
    display_repl_status("stopped")
    a.assoc(state(), "repl", nil)
    a.assoc(state(), "project-root", nil)
    return a.assoc(state(), "project-syspath", nil)
  else
    return nil
  end
end
_2amodule_2a["stop"] = stop
local function start()
  if state("repl") then
    return log.append({(comment_prefix .. "Can't start, REPL is already running."), (comment_prefix .. "Stop the REPL with " .. config["get-in"]({"mapping", "prefix"}) .. cfg({"mapping", "stop"}))}, {["break?"] = true})
  else
    do
      local project_root = find_project_root()
      if project_root then
        a.assoc(state(), "project-root", project_root)
        local project_syspath = fs["join-path"]({project_root, "jpm_tree", "lib"})
        if nvim.fn.isdirectory(project_syspath) then
          a.assoc(state(), "project-syspath", project_syspath)
        else
        end
      else
        log.append({(comment_prefix .. "No project.janet file in parent directories")})
      end
    end
    local _19_
    if state("project-syspath") then
      _19_ = (cfg({"command"}) .. " -m " .. state("project-syspath"))
    else
      _19_ = cfg({"command"})
    end
    local function _21_()
      return display_repl_status("started")
    end
    local function _22_(err)
      return display_repl_status(err)
    end
    local function _23_(code, signal)
      if (("number" == type(code)) and (code > 0)) then
        log.append({(comment_prefix .. "process exited with code " .. code)})
      else
      end
      if (("number" == type(signal)) and (signal > 0)) then
        log.append({(comment_prefix .. "process exited with signal " .. signal)})
      else
      end
      return stop()
    end
    local function _26_(msg)
      return log.append(format_message(msg))
    end
    a.assoc(state(), "repl", stdio.start({["prompt-pattern"] = cfg({"prompt_pattern"}), cmd = _19_, ["on-success"] = _21_, ["on-error"] = _22_, ["on-exit"] = _23_, ["on-stray-output"] = _26_}))
    return send_to_repl(prep_code(prelude), {})
  end
end
_2amodule_2a["start"] = start
local function on_load()
  return start()
end
_2amodule_2a["on-load"] = on_load
local function on_filetype()
  mapping.buf("JanetStart", cfg({"mapping", "start"}), start, {desc = "Start the REPL"})
  return mapping.buf("JanetStop", cfg({"mapping", "stop"}), stop, {desc = "Stop the REPL"})
end
_2amodule_2a["on-filetype"] = on_filetype
local function on_exit()
  return stop()
end
_2amodule_2a["on-exit"] = on_exit
return _2amodule_2a
