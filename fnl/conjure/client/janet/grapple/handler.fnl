(local {: autoload} (require :nfnl.module))
(local log (autoload :conjure.log))
(local n (autoload :nfnl.core))
(local state (autoload :conjure.client.janet.grapple.state))
(local str (autoload :nfnl.string))

(fn upcase [s n]
  (let [start (string.sub s 1 n)
        rest (string.sub s (+ n 1))]
    (.. (string.upper start) rest)))

(fn error-msg? [msg]
  (= "err" msg.tag))

(fn display-error [msg]
  (log.append [(.. "# " msg.msg)]))

(fn handle-sess-new [resp]
  (n.assoc (state.get :conn) :session resp.sess)
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
    (error-msg? resp)
    (log.append [resp.msg])

    (and (= "out" resp.tag) (= "out" resp.ch))
    (log.append [(.. "# (out) " resp.val)])

    (and (= "out" resp.tag) (= "err" resp.ch))
    (log.append [(.. "# (err) " resp.val)])

    (log.append [resp.val])))

(fn handle-env-doc [resp]
  (if
    (error-msg? resp)
    (log.append [resp.msg])

    (= "ret" resp.tag)
    (let [[path line col] resp.janet/sm
          buf (vim.api.nvim_create_buf false true)
          lines (n.concat [resp.janet/type
                           (.. path " on line " line ", column " col)
                           ""]
                          (str.split resp.val "\n"))
          _ (vim.api.nvim_buf_set_lines buf 0 -1 false lines)
          width 50
          height 10
          win-opts {:relative "cursor"
                    :width width
                    :height height
                    :col 0
                    :row 1
                    :anchor "NW"
                    :style "minimal"
                    :border "rounded"}
          win (vim.api.nvim_open_win buf false win-opts)]
      (vim.api.nvim_buf_set_option buf "wrap" true)
      (vim.api.nvim_buf_set_option buf "linebreak" true)
      (vim.api.nvim_buf_set_option buf "filetype" "markdown")
      (vim.api.nvim_create_autocmd :CursorMoved
                                   {:once true
                                    :callback (fn []
                                                (vim.api.nvim_win_close win true)
                                                (vim.api.nvim_buf_delete buf {:force true})
                                                nil)}))))

(fn handle-message [msg]
  (when msg
   (if
    (error-msg? msg)
    (display-error msg)

    (= "sess.new" msg.op)
    (handle-sess-new msg)

    (= "sess.end" msg.op)
    (handle-sess-end msg)

    (= "sess.list" msg.op)
    (handle-sess-list msg)

    (= "serv.info" msg.op)
    (handle-sess-info msg)

    (= "serv.stop" msg.op)
    (handle-serv-stop msg)

    (= "serv.rest" msg.op)
    (handle-serv-rest msg)

    (= "env.eval" msg.op)
    (handle-env-eval msg)

    (= "env.load" msg.op)
    (handle-env-load msg)

    (= "env.stop" msg.op)
    (handle-env-stop msg)

    (= "env.doc" msg.op)
    (handle-env-doc msg)

    (= "env.cmpl" msg.op)
    (handle-env-cmpl msg)

    (do
      (log.append ["# Unrecognised message"])))))

{: handle-message}
