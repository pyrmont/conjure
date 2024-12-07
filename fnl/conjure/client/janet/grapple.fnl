(local {: autoload} (require :nfnl.module))
(local a (autoload :conjure.aniseed.core))
(local client (autoload :conjure.client))
(local config (autoload :conjure.config))
(local log (autoload :conjure.log))
(local mapping (autoload :conjure.mapping))
(local remote (autoload :conjure.remote.mrepl))
(local s (autoload :nfnl.string))
(local text (autoload :conjure.text))
(local ts (autoload :conjure.tree-sitter))

(local buf-suffix ".janet")
(local comment-prefix "# ")
(local comment-node? ts.lisp-comment-node?)
(local form-node? ts.node-surrounded-by-form-pair-chars?)

(config.merge
  {:client
   {:janet
    {:mrepl
     {:connection {:default_host "127.0.0.1"
                   :default_port "3737"}}}}})

(when (config.get-in [:mapping :enable_defaults])
  (config.merge
    {:client
     {:janet
      {:mrepl
       {:mapping {:connect "cc"
                  :disconnect "cd"}}}}}))

(local state (client.new-state #(do {:conn nil})))

(fn upcase [s n]
  (let [start (string.sub s 1 n)
        rest (string.sub s (+ n 1))]
    (.. (string.upper start) rest)))

(fn error-msg? [msg]
  (= "err" msg.tag))

(fn display-error [msg]
  (log.append [(.. "# " msg.msg)]))

(fn handle-sess-new [resp]
  (a.assoc (state :conn) :session resp.sess)
  (let [[impl-name impl-ver] resp.janet/impl
        [serv-name serv-ver] resp.janet/serv]
    (log.append [(.. "# Connected to "
                     (upcase serv-name 1)
                     " v"
                     serv-ver
                     " running "
                     (upcase impl-name 1)
                     " v"
                     impl-ver
                     " as session "
                     resp.sess)])))

(fn handle-env-eval [resp]
  (if
    (= "out" resp.tag)
    (log.append [(.. "# (out) " resp.val)])

    (= "err" resp.tag)
    (log.append [(.. "# (err) " resp.value)])

    (log.append [resp.val])))

(fn handle-message [msg]
  (when msg
   (if
    (error-msg? msg)
    (display-error msg)

    (= "sess.new" msg.op)
    (handle-sess-new msg)

    (= "env.eval" msg.op)
    (handle-env-eval msg)

    (do
      (log.append ["# Unrecognised message"])))))

(fn with-conn-or-warn [f opts]
  (let [conn (state :conn)]
    (if conn
      (f conn)
      (log.append ["# No connection"]))))

(fn connected? []
  (if (state :conn)
    true
    false))

(fn display-conn-status [status]
  (with-conn-or-warn
    (fn [conn]
      (log.append
        [(.. "# " conn.host ":" conn.port " (" status ")")]
        {:break? true}))))

(fn disconnect []
  (with-conn-or-warn
    (fn [conn]
      (conn.destroy)
      (display-conn-status :disconnected)
      (a.assoc (state) :conn nil))))

(fn connect [opts]
  (let [opts (or opts {})
        host (or opts.host (config.get-in [:client :janet :mrepl :connection :default_host]))
        port (or opts.port (config.get-in [:client :janet :mrepl :connection :default_port]))]

    ; TODO: don't disconnect
    (when (state :conn)
      (disconnect))

    (local conn
      (remote.connect
        {:host host
         :port port
         :lang "net.inqk/janet/1.0"

         :on-message handle-message

         :on-failure
         (fn [err]
           (display-conn-status err)
           (disconnect))

         :on-success
         (fn []
           (a.assoc (state) :conn conn)
           (display-conn-status :connected))

         :on-error
         (fn [err]
           (if err
             (display-conn-status err)
             (disconnect)))}))))

(fn try-ensure-conn []
  (when (not (connected?))
    (connect {:silent? true})))

(fn eval-str [opts]
  (try-ensure-conn)
  (let [conn (state :conn)]
    (conn.send {:op "env.eval"
                :code opts.code
                :ns opts.file-path
                :janet/col (a.get-in opts.range [:start 2] 1)
                :janet/line (a.get-in opts.range [:start 1] 1)})))

(fn doc-str [opts]
  (try-ensure-conn)
  (eval-str (a.update opts :code #(.. "(doc " $1 ")"))))

(fn eval-file [opts]
  (try-ensure-conn)
  (eval-str
    (a.assoc opts :code (.. "(do (dofile \"" opts.file-path
                            "\" :env (fiber/getenv (fiber/current))) nil)"))))

(fn on-filetype []
  (mapping.buf
    :JanetDisconnect
    (config.get-in [:client :janet :mrepl :mapping :disconnect])
    disconnect
    {:desc "Disconnect from the REPL"})

  (mapping.buf
    :JanetConnect
    (config.get-in [:client :janet :mrepl :mapping :connect])
    #(connect)
    {:desc "Connect to a REPL"}))

(fn on-load []
  (connect {}))

(fn on-exit []
  (disconnect))

{: buf-suffix
 : comment-node?
 : comment-prefix
 : connect
 : disconnect
 : doc-str
 : eval-file
 : eval-str
 : form-node?
 : on-exit
 : on-filetype
 : on-load}
