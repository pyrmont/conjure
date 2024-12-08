(local {: autoload} (require :nfnl.module))
(local log (autoload :conjure.log))
(local n (autoload :nfnl.core))
(local state (autoload :conjure.client.janet.grapple.state))

(fn sess-new [conn opts]
  (conn.send {:op "sess.new"}))

(fn sess-end [conn opts]
  (conn.send {:op "sess.end"}))

(fn sess-list [conn opts]
  (conn.send {:op "sess.list"}))

(fn serv-info [conn opts]
  (conn.send {:op "serv.info"}))

(fn serv-stop [conn opts]
  (conn.send {:op "serv.stop"}))

(fn serv-rest [conn opts]
  (conn.send {:op "serv.rest"}))

(fn env-eval [conn opts]
  (conn.send {:op "env.eval"
              :ns opts.file-path
              :code opts.code
              :col (n.get-in opts.range [:start 2] 1)
              :line (n.get-in opts.range [:start 1] 1)}))

(fn env-load [conn opts]
  (conn.send {:op "env.load"
              :path opts.file-path}))

(fn env-stop [conn opts]
  (log.append ["# env.stop is not supported"]))

(fn env-doc [conn opts]
  (conn.send {:op "env.doc"
              :ns opts.file-path
              :sym opts.code}))

(fn env-cmpl [conn opts]
  (conn.send {:op "env.cmpl"
              :ns opts.file-path
              :sym opts.code}))

{: sess-new
 : sess-end
 : sess-list
 : serv-info
 : serv-stop
 : serv-rest
 : env-eval
 : env-load
 : env-stop
 : env-doc
 : env-cmpl}
