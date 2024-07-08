(module conjure.client.janet.mrepl
  {autoload {a conjure.aniseed.core
             str conjure.aniseed.string
             nvim conjure.aniseed.nvim
             client conjure.client
             config conjure.config
             fs conjure.fs
             log conjure.log
             mapping conjure.mapping
             stdio conjure.remote.stdio
             ts conjure.tree-sitter}
   require-macros [conjure.macros]})

(config.merge
  {:client
   {:janet
    {:mrepl
     {:mapping {:start "cs"
                :stop "cS"}

      ;; -n -> disables ansi color
      ;; -s -> raw stdin (no getline functionality)
      :command "janet -n -s"

      ;; Example prompts:
      ;;
      ;; "repl:23:>"
      ;; "repl:8:(>"
      ;;
      :prompt_pattern "repl:[0-9]+:[^>]*> "
      }}}})

(def- cfg (config.get-in-fn [:client :janet :mrepl]))

(defonce- state (client.new-state #(do {:repl nil
                                        :project-root nil
                                        :project-syspath nil})))

(def buf-suffix ".janet")
(def comment-prefix "# ")
(def form-node? ts.node-surrounded-by-form-pair-chars?)

(def prelude
  "__CONJURE_EMBED__")

(defn unbatch [msgs]
  {:out (->> msgs
          (a.map #(or (a.get $1 :out) (a.get $1 :err)))
          (str.join ""))})

(defn- format-message [msg]
  (->> (str.split msg.out "\n")
       (a.filter #(~= "" $1))))

(defn- send-to-repl [msg opts]
  (let [repl (state :repl)]
    (if repl
      (repl.send
        msg
        (fn [msgs]
          (let [lines (-> msgs unbatch format-message)]
            (when opts.on-result
              (opts.on-result (a.last lines)))
            ; (when (not opts.silent)
            ;   (log.append lines))
            (log.append lines)
            ))
        {:batch? true})
      (log.append [(.. comment-prefix "No REPL running")]))))

(defn- supervisor-msg [cmd payload]
  (.. "\xFF{:cmd " cmd " :payload " payload "}\n"))

(defn- tell-supervisor [cmd opts]
  (send-to-repl (case cmd
                  :update-source
                  (let [path (if (state :project-path)
                               (fs.resolve-relative-to opts.file-path (state :project-path))
                               opts.file-path)]
                    (supervisor-msg ":update/source" (.. "{:path `" path "` :line " (a.get-in opts.range [:start 1] 1) " :col " (a.get-in opts.range [:start 2] 0) "}"))))
                {:silent true}))

(defn- prep-code [s]
  (.. s "\n"))

(defn eval-str [opts]
  (tell-supervisor :update-source opts)
  (send-to-repl (prep-code opts.code) opts))

(defn eval-file [opts]
  (eval-str (a.assoc opts :code (a.slurp opts.file-path))))

(defn doc-str [opts]
  (a.update opts :code #(.. "(doc " $1 ")"))
  (send-to-repl (prep-code opts.code) opts))

(defn- display-repl-status [status]
  (let [repl (state :repl)]
    (when repl
      (log.append
        [(.. comment-prefix (a.pr-str (a.get-in repl [:opts :cmd])) " (" status ")")]
        {:break? true}))))

(defn- find-project-root []
  (let [pwd (nvim.fn.expand "%:p:h")
        file-path (fs.upwards-file-search ["project.janet"] pwd)]
    (when file-path
      (fs.parent-dir (nvim.fn.fnamemodify file-path ":p")))))

(defn stop []
  (let [repl (state :repl)]
    (when repl
      (repl.destroy)
      (display-repl-status :stopped)
      (a.assoc (state) :repl nil)
      (a.assoc (state) :project-root nil)
      (a.assoc (state) :project-syspath nil))))

(defn start []
  (if (state :repl)
    (log.append [(.. comment-prefix "Can't start, REPL is already running.")
                 (.. comment-prefix "Stop the REPL with "
                     (config.get-in [:mapping :prefix])
                     (cfg [:mapping :stop]))]
                {:break? true})
    (do
      (let [project-root (find-project-root)]
        (if project-root
          (do
            (a.assoc (state) :project-root project-root)
            (let [project-syspath (fs.join-path [project-root "jpm_tree" "lib"])]
              (when (nvim.fn.isdirectory project-syspath)
                (a.assoc (state) :project-syspath project-syspath))))
          (log.append [(.. comment-prefix "No project.janet file in parent directories")])))
      (a.assoc
        (state) :repl
        (stdio.start
          {:prompt-pattern
           (cfg [:prompt_pattern])

           :cmd
           (if (state :project-syspath)
             (.. (cfg [:command]) " -m " (state :project-syspath))
             (cfg [:command]))

           :on-success
           (fn []
             (display-repl-status :started))

           :on-error
           (fn [err]
             (display-repl-status err))

           :on-exit
           (fn [code signal]
             (when (and (= :number (type code)) (> code 0))
               (log.append [(.. comment-prefix "process exited with code " code)]))
             (when (and (= :number (type signal)) (> signal 0))
               (log.append [(.. comment-prefix "process exited with signal " signal)]))
             (stop))

           :on-stray-output
           (fn [msg]
             (log.append (format-message msg)))}))
      (send-to-repl (prep-code prelude) {}))))

(defn on-load []
  (start))

(defn on-filetype []
  (mapping.buf
    :JanetStart (cfg [:mapping :start])
    start
    {:desc "Start the REPL"})

  (mapping.buf
    :JanetStop (cfg [:mapping :stop])
    stop
    {:desc "Stop the REPL"}))

(defn on-exit []
  (stop))

