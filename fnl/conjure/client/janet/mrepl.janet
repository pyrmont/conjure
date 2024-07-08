(do
  (def mb 255)

  (var env nil)
  (var path nil)
  (var cnt 0)

  (defn supervise
    ```
    Supervises the current evaluation

    mrepl allows a client to send control instructions to the supervisor by
    prepending a magic byte to the beginning of a new line. If a magic byte is
    present, this function is used to parse the instruction.

    Only one instruction is supported currently. This instruction changes the
    source file and changes the evaluation environment, either using an
    existing environment from the module cache or creating a new environment
    (saving it to the module cache).
    ```
    [buf p]
    (def msg (parse (buffer/slice buf 1)))
    (def cmd (get msg :cmd))
    (case (get msg :cmd)
      :update/source
      (do
        (def {:path new-path :line line :col col} (get msg :payload))
        (parser/where p line col)
        (unless (= path new-path)
          (parser/flush p)
          (set env (or (get module/cache new-path)
                       (do
                         (def new-env (make-env))
                         (put module/cache new-path new-env)
                         new-env)))
          (set path new-path))
        [:source path])))

  (defn chunks
    ```
    Gets chunk of input

    When evaluating input in `run-context`, this function adds the input to the
    buffer to process. If the input begins with a magic byte, the `supervise`
    function is called.
    ```
    [buf p]
    (def prmpt (string "repl:" (++ cnt) ":" (:state p :delimiters) "> "))
    (file/write stdout prmpt)
    (file/flush stdout)
    (file/read stdin :line buf)
    (if (= mb (get buf 0))
      (supervise buf p)
      (do
        (when (zero? (length buf))
          (put env :exit true)
          (put env :exit-value false)))))

  (defn on-status
    ```
    Handles status signals

    Evaluated input is run in a fiber by `run-context`. This function is used
    to determine what to do based upon the signal of the fiber.
    ```
    [f x]
    (def fs (fiber/status f))
    (if (= :dead fs)
      (do
        (put env '_ @{:value x})
        (def pf (get env *pretty-format* "%q"))
        (try
          (printf pf x)
          ([e]
            (eprintf "bad pretty format %v: %v" pf e)
            (eflush)))
        (flush))
      (do
        (debug/stacktrace f x "")
        (eflush)
        (if (get env :debug) (debugger f 1)))))

  (def lint-levels
    {:none 0
     :relaxed 1
     :normal 2
     :strict 3
     :all math/inf})

  (defn run-context
    ```
    Runs code in a context

    This function is an almost unmodified version of Janet's core `run-context`
    function. The only changes are removing the `env` binding from the initial
    def statement, removing the default setup for the `env` binding and
    avoiding all uses of quotation marks.
    ```
    [opts]
    (def {:chunks chunks
          :on-status onstatus
          :on-compile-error on-compile-error
          :on-compile-warning on-compile-warning
          :on-parse-error on-parse-error
          :fiber-flags guard
          :evaluator evaluator
          :source default-where
          :parser parser
          :read read
          :expander expand} opts)
    (default chunks (fn chunks [buf p] (getline "" buf env)))
    (default onstatus debug/stacktrace)
    (default on-compile-error bad-compile)
    (default on-compile-warning warn-compile)
    (default on-parse-error bad-parse)
    (default evaluator (fn evaluate [x &] (x)))
    (default default-where :<anonymous>)
    (default guard :ydt)

    (var where default-where)

    (if (string? where)
      (put env *current-file* where))

    # Evaluate 1 source form in a protected manner
    (def lints @[])
    (defn eval1 [source &opt l c]
      (def source (if expand (expand source) source))
      (var good true)
      (var resumeval nil)
      (def f
        (fiber/new
          (fn []
            (array/clear lints)
            (def res (compile source env where lints))
            (unless (empty? lints)
              # Convert lint levels to numbers.
              (def levels (get env *lint-levels* lint-levels))
              (def lint-error (get env *lint-error*))
              (def lint-warning (get env *lint-warn*))
              (def lint-error (or (get levels lint-error lint-error) 0))
              (def lint-warning (or (get levels lint-warning lint-warning) 2))
              (each [level line col msg] lints
                (def lvl (get lint-levels level 0))
                (cond
                  (<= lvl lint-error) (do
                                        (set good false)
                                        (on-compile-error msg nil where (or line l) (or col c)))
                  (<= lvl lint-warning) (on-compile-warning msg level where (or line l) (or col c)))))
            (when good
              (if (= (type res) :function)
                (evaluator res source env where)
                (do
                  (set good false)
                  (def {:error err :line line :column column :fiber errf} res)
                  (on-compile-error err errf where (or line l) (or column c))))))
          guard
          env))
      (while (fiber/can-resume? f)
        (def res (resume f resumeval))
        (when good (set resumeval (onstatus f res)))))

    # Reader version
    (when read
      (forever
        (if (in env :exit) (break))
        (eval1 (read env where)))
      (break (in env :exit-value env)))

    # The parser object
    (def p (or parser (parser/new)))
    (def p-consume (p :consume))
    (def p-produce (p :produce))
    (def p-status (p :status))
    (def p-has-more (p :has-more))

    (defn parse-err
      [p where]
      (def f (coro (on-parse-error p where)))
      (fiber/setenv f env)
      (resume f))

    (defn produce []
      (def tup (p-produce p true))
      [(in tup 0) ;(tuple/sourcemap tup)])

    # Loop
    (def buf @"")
    (var parser-not-done true)
    (while parser-not-done
      (if (env :exit) (break))
      (buffer/clear buf)
      (match (chunks buf p)
        :cancel
        (do
          # A :cancel chunk represents a cancelled form in the REPL, so reset.
          (:flush p)
          (buffer/clear buf))

        [:source new-where]
        (do
          (set where new-where)
          (if (string? new-where)
            (put env *current-file* new-where)))

        (do
          (var pindex 0)
          (var pstatus nil)
          (def len (length buf))
          (when (= len 0)
            (:eof p)
            (set parser-not-done false))
          (while (> len pindex)
            (+= pindex (p-consume p buf pindex))
            (while (p-has-more p)
              (eval1 ;(produce))
              (if (env :exit) (break)))
            (when (= (p-status p) :error)
              (parse-err p where)
              (if (env :exit) (break)))))))

    # Check final parser state
    (unless (env :exit)
      (while (p-has-more p)
        (eval1 ;(produce))
        (if (env :exit) (break)))
      (when (= (p-status p) :error)
        (parse-err p where)))

    (put env :exit nil)
    (in env :exit-value env))

  (defn repl
    ```
    Creates a REPL

    This function creates a REPL that uses mrepl's `chunks` and `on-status`
    functions.
    ```
    []
    (set env (make-env))
    (def p (parser/new))
    (forever
      (unless (run-context {:chunks chunks
                            :on-status on-status
                            :parser p})
        (break))))

  (put root-env :redef true)

  (print "[mrepl] Loaded prelude")

  (repl))
