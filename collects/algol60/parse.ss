#cs(module parse mzscheme
     (require (lib "lex.ss" "parser-tools")
              (lib "yacc.ss" "parser-tools")
              "prims.ss")
     
     (define-lex-abbrevs [lex:letter (: (- #\a #\z) (- #\A #\Z))]
                         [lex:digit (- #\0 #\9)]
                         [lex:whitespace (: #\newline #\return #\tab #\space #\vtab)]
                         [lex:comment (@ (* (lex:whitespace)) comment (* (^ #\;)) #\;)])
     
     (define-tokens non-terminals (<logical-value> 
                                   <type> <identifier> 
                                   <unsigned-integer> <unsigned-float> <string>
                                   
                                   GOTO IF THEN ELSE FOR DO STEP UNTIL WHILE
                                   OWN ARRAY STRING PROCEDURE SWITCH LABEL VALUE
                                   BEGIN END
                                   POWER PLUS MINUS TIMES SLASH DIVIDE
                                   LESS LESS-OR-EQUAL EQUAL GREATER-OR-EQUAL GREATER NOT-EQUAL ASSIGN
                                   NEGATE AND OR IMPLIES EQUIV
                                   COMMA COLON SEMICOLON
                                   OPEN CLOSE OPENSQ CLOSESQ
                                   EOF))
     
     (define-syntax (token stx)
       (syntax-case stx ()
         [(_ name val)
          (identifier? (syntax name))
          (let ([name (syntax name)])
            (with-syntax ([token-name (datum->syntax-object
                                       name
                                       (string->symbol
                                        (format "token-~a" (syntax-e name))))]
                          [source-name (datum->syntax-object name 'source-name)]
                          [get-start-pos (datum->syntax-object name 'get-start-pos)]
                          [get-end-pos (datum->syntax-object name 'get-end-pos)])
              (syntax (let ([start (get-start-pos)]
                            [end (get-end-pos)])
                        (token-name (datum->syntax-object 
                                     #f val
                                     (list
                                      source-name
                                      (position-line start)
                                      (position-col start)
                                      (position-offset start)
                                      (- (position-offset end)
                                         (position-offset start)))))))))]))
     (define-syntax (ttoken stx)
       (syntax-case stx ()
         [(_ name)
          (identifier? (syntax name))
          (syntax (token name 'name))]))
     
     (define (lexer source-name)
       (lex
        [(+ (lex:whitespace)) (void)]
        [true (token <logical-value> #t)]
        [false (token <logical-value> #f)]
        [real (token <type> 'real)]
        [integer (token <type> 'integer)]
        [Boolean (token <type> 'boolean)]
        [goto (ttoken GOTO)]
        [if (ttoken IF)]
        [then (ttoken THEN)]
        [else (ttoken ELSE)]
        [for (ttoken FOR)]
        [do (ttoken DO)]
        [step (ttoken STEP)]
        [until (ttoken UNTIL)]
        [while (ttoken WHILE)]
        [own (ttoken OWN)]
        [array (ttoken ARRAY)]
        [string (ttoken STRING)]
        [procedure (ttoken PROCEDURE)]
        [switch (ttoken SWITCH)]
        [label (ttoken LABEL)]
        [value (ttoken VALUE)]
        [(@ begin (lex:comment)) (ttoken BEGIN)]
        [begin (ttoken BEGIN)]
        [(@ end (lex:comment)) (ttoken BEGIN)]
        [end (ttoken END)]
        [^ (token POWER #'expt)]
        [+ (token PLUS #'+)]
        [- (token MINUS #'-)]
        [* (token TIMES #'*)]
        [/ (token SLASH #'/)]
        [div (token DIVIDE #'quotient)]
        [< (token LESS #'<)]
        [<= (token LESS-OR-EQUAL #'<=)]
        [= (token EQUAL #'=)]
        [> (token GREATER #'>)]
        [>= (token GREATER-OR-EQUAL #'>=)]
        [!= (token NOT-EQUAL #'!=)]
        [! (token NEGATE #'!)]
        [& (token AND #'&)]
        [#\| (token OR #'\|)]
        [=> (token IMPLIES #'=>)]
        [== (token EQUIV #'==)]
        [:= (ttoken ASSIGN)]
        [#\, (ttoken COMMA)]
        [: (ttoken COLON)]
        [(@ #\; (lex:comment)) (ttoken SEMICOLON)]
        [#\; (ttoken SEMICOLON)]
        [#\( (ttoken OPEN)]
        [#\) (ttoken CLOSE)]
        [#\[ (ttoken OPENSQ)]
        [#\] (ttoken CLOSESQ)]
        [(@ (lex:letter) (* (: (lex:letter) (lex:digit)))) (token <identifier> (string->symbol (get-lexeme)))]
        [(+ (lex:digit)) (token <unsigned-integer> (string->number (get-lexeme)))]
        [(: (@ (+ (lex:digit)) #\. (* (lex:digit)))
            (@ (* (lex:digit)) #\. (+ (lex:digit)))) (token <unsigned-float> (string->number (get-lexeme)))]
        [(@ #\` (* (^ #\' #\`)) #\') (let ([s (get-lexeme)])
                                       (token <string> (substring s 1 (sub1 (string-length s)))))]
        [(eof) (ttoken EOF)]))

     (define parse
       (parser
        (tokens non-terminals)
        (start <program>)
        (end EOF)
        (error (lambda () (error "parse error")))
        (grammar 
         ;; ==================== Expressions ====================
         (<expression> [(<arithmetic-expression>) $1]
                       [(<Boolean-expression>) $1]
                       [(<designational-expression>) $1])
         ;; -------------------- Numbers --------------------
         (<arithmetic-expression> [(<simple-arithmetic-expression>) $1]
                                  [(IF <Boolean-expression> 
                                       THEN <simple-arithmetic-expression> 
                                       ELSE <arithmetic-expression>)
                                   (make-a60:if $2 $4 $6)])
         (<simple-arithmetic-expression> [(<term>) $1]
                                         [(<adding-operator> <term>) (make-a60:unary $1 $2)]
                                         [(<simple-arithmetic-expression> <adding-operator> <term>) 
                                          (make-a60:binary $2 $1 $3)])
         (<term> [(<factor>) $1]
                 [(<term> <multiplying-operator> <factor>) (make-a60:binary $2 $1 $3)])
         (<factor> [(<primary>) $1]
                   [(<factor> POWER <primary>) (make-a60:binary $2 $1 $3)])
         (<adding-operator> [(PLUS) $1]
                            [(MINUS) $1])
         (<multiplying-operator> [(TIMES) $1]
                                 [(SLASH) $1]
                                 [(DIVIDE) $1])
         (<primary> [(<unsigned-integer>) $1]
                    [(<unsigned-float>) $1]
                    [(<variable>) $1]
                    [(<function-designator>) $1]
                    [(OPEN <arithmetic-expression> CLOSE) $2])
         ;; -------------------- Booleans --------------------
         (<relational-operator> [(LESS) $1]
                                [(LESS-OR-EQUAL) $1]
                                [(EQUAL) $1]
                                [(GREATER-OR-EQUAL) $1]
                                [(GREATER) $1]
                                [(NOT-EQUAL) $1])
         (<relation> [(<simple-arithmetic-expression> <relational-operator> <simple-arithmetic-expression>)
                      (make-a60:binary $2 $1 $3)])
         (<Boolean-primary> [(<logical-value>) $1]
                            [(<variable>) $1]
                            [(<function-designator>) $1]
                            [(<relation>) $1]
                            [(OPEN <Boolean-expression> CLOSE) $2])
         (<Boolean-secondary> [(<Boolean-primary>) $1]
                              [(NEGATE <Boolean-primary>) (make-a60:unary $1 $2)])
         (<Boolean-factor> [(<Boolean-secondary>) $1]
                           [(<Boolean-factor> AND <Boolean-secondary>) (make-a60:binary $2 $1 $3)])
         (<Boolean-term> [(<Boolean-factor>) $1]
                         [(<Boolean-term> OR <Boolean-factor>)  (make-a60:binary $2 $1 $3)])
         
         (<implication> [(<Boolean-term>) $1]
                        [(<implication> IMPLIES <Boolean-term>) (make-a60:binary $2 $1 $3)])
         (<simple-Boolean> [(<implication>) $1]
                           [(<simple-Boolean> EQUIV <implication>) (make-a60:binary $2 $1 $3)])
         (<Boolean-expression> [(<simple-Boolean>) $1]
                               [(IF <Boolean-expression> 
                                    THEN <simple-Boolean> 
                                    ELSE <Boolean-expression>)
                                (make-a60:if $2 $4 $6)])
         ;; -------------------- Designationals --------------------
         (<label> [(<identifier>) $1]
                  [(<unsigned-integer>) $1])
         (<switch-identifier> [(<identifier>) $1])
         (<switch-designator> [(<switch-identifier> OPENSQ <arithmetic-expression> CLOSESQ)
                               (make-a60:subscript $1 $3)])
         (<simple-designational-expression> [(<label>) $1]
                                            [(<switch-designator>) $1]
                                            [(OPEN <designational-expression> CLOSE) $2])
         (<designational-expression> [(<simple-designational-expression>) $1]
                                     [(IF <Boolean-expression> 
                                          THEN <simple-designational-expression> 
                                          ELSE <designational-expression>)
                                      (make-a60:if $2 $4 $6)])
         ;; -------------------- Variables --------------------
         (<subscript-list> [(<arithmetic-expression>) (list $1)]
                           [(<subscript-list> COMMA <arithmetic-expression>) (append $1 (list $2))])
         (<subscripted-variable> [(<identifier> OPENSQ <subscript-list> CLOSESQ) (make-a60:variable $1 $3)])
         (<variable> [(<identifier>) (make-a60:variable $1 null)]
                     [(<subscripted-variable>) $1])
         ;; -------------------- Function calls --------------------
         (<function-designator> [(<identifier> <actual-parameter-part>) (make-a60:app $1 $2)])
         ;; ==================== Statements ====================
         (<unlabelled-basic-statement> [(<assignment-statement>) $1]
                                       [(<go-to-statement>) $1]
                                       [(<dummy-statement>) $1]
                                       [(<procedure-statement>) $1])
         (<basic-statement> [(<unlabelled-basic-statement>) $1]
                            [(<label> COLON <basic-statement>) (make-a60:label $1 $3)])
         (<unconditional-statement> [(<basic-statement>) $1]
                                    [(<compound-statement>) $1]
                                    [(<block>) $1])
         (<statement> [(<unconditional-statement>) $1]
                      [(<conditional-statement>) $1]
                      [(<for-statement>) $1])
         (<compound-tail> [(<statement> END) (list $1)]
                          [(<statement> SEMICOLON <compound-tail>) (cons $1 $3)])
         (<block-head> [(BEGIN <declaration>) (list $2)]
                       [(<block-head> SEMICOLON <declaration>) (append $1 (list $3))])
         (<unlabelled-block> [(<block-head> SEMICOLON <compound-tail>) (make-a60:block $1 $3)])
         (<unlabelled-compound> [(BEGIN <compound-tail>) (make-a60:compound $2)])
         
         (<compound-statement> [(<unlabelled-compound>) $1]
                               [(<label> COLON <compound-statement>) (make-a60:label $1 $3)])
         (<block> [(<unlabelled-block>) $1]
                  [(<label> COLON <block>) (make-a60:label $1 $3)])
         ;; -------------------- assignment --------------------
         (<left-part> [(<variable> ASSIGN) $1])
         (<left-part-list> [(<left-part>) (list $1)]
                           [(<left-part-list> <left-part>) (append $1 (list $2))])
         (<assignment-statement> [(<left-part-list> <arithmetic-expression>) (make-a60:assign $1 $2)]
                                 [(<left-part-list> <Boolean-expression>) (make-a60:assign $1 $2)])
         ;; -------------------- goto --------------------
         (<go-to-statement> [(GOTO <designational-expression>) (make-a60:goto $2)])
         ;; -------------------- dummy --------------------
         (<dummy-statement> [() (make-a60:compound null)])
         ;; -------------------- conditional --------------------
         (<conditional-statement> [(IF <Boolean-expression> THEN <unconditional-statement>)
                                   (make-a60:branch $2 $4 (make-a60:compound null))]
                                  [(IF <Boolean-expression> THEN <unconditional-statement> ELSE <statement>)
                                   (make-a60:branch $2 $4 $6)]
                                  [(IF <Boolean-expression> THEN <for-statement>)
                                   (make-a60:branch $2 $4 (make-a60:compound null))]
                                  [(<label> COLON <conditional-statement>) (make-a60:label $1 $3)])
         ;; -------------------- for --------------------
         (<for-list-element> [(<arithmetic-expression>) (make-a60:for-number $1)]
                             [(<arithmetic-expression> STEP <arithmetic-expression> UNTIL <arithmetic-expression>)
                              (make-a60:for-step $1 $3 $5)]
                             [(<arithmetic-expression> WHILE <Boolean-expression>) (make-a60:for-while $1 $3)])
         (<for-list> [(<for-list-element>) (list $1)]
                     [(<for-list> COMMA <for-list-element>) (append $1 (list $3))])
         (<for-statement> [(FOR <variable> ASSIGN <for-list> DO <statement>)
                           (make-a60:for $2 $4 $6)]
                          [(<label> COLON <for-statement>) (make-a60:label $1 $3)])
         ;; -------------------- procedure statement --------------------
         (<actual-parameter> [(<string>) $1]
                             [(<expression>) $1]
                             ; [(<identifier>) $1] ; switch, array, or procedure
                             )
         (<parameter-delimiter> [(COMMA) (void)]
                                [(CLOSE <identifier> COLON OPEN) (void)]) ;; <identifier> was <letter-string>!
         (<actual-parameter-list> [(<actual-parameter>) (list $1)]
                                  [(<actual-parameter-list> <parameter-delimiter> <actual-parameter>)
                                   (append $1 (list $3))])
         (<actual-parameter-part> ; [() null] ; <<< omitted, because we'll parse it as a variable at first
                                  [(OPEN <actual-parameter-list> CLOSE) $2])
         (<procedure-statement> [(<identifier> <actual-parameter-part>) (make-a60:call $1 $2)])
         ;; ==================== Declarations ====================
         (<declaration> [(<type-declaration>) $1]
                        [(<array-declaration>) $1]
                        [(<switch-declaration>) $1]
                        [(<procedure-declaration>) $1])
         ;; -------------------- Simple --------------------
         (<type-list> [(<identifier>) (list $1)]
                      [(<identifier> COMMA <type-list>) (cons $1 $3)])
         (<local-or-own-type> [(<type>) $1]
                              [(OWN <type>) (box $2)]) ; box => own
         (<type-declaration> [(<local-or-own-type> <type-list>) (make-a60:type-decl $1 $2)])
         ;; -------------------- Arrays --------------------
         (<bound-pair> [(<arithmetic-expression> COLON <arithmetic-expression>) (cons $1 $3)])
         (<bound-pair-list> [(<bound-pair>) (list $1)]
                            [(<bound-pair-list> COMMA <bound-pair>) (append $1 (list $3))])
         (<array-segment> [(<identifier> OPENSQ <bound-pair-list> CLOSESQ) (list (cons $1 $3))]
                          [(<identifier> COMMA <array-segment>) (cons (cons $1 (cdar $3)) $3)])
         (<array-list> [(<array-segment>) $1]
                       [(<array-list> COMMA <array-segment>) (append $1 $3)])
         (<array-declaration> [(ARRAY <array-list>) (make-a60:array-decl #f $2)]
                              [(<local-or-own-type> ARRAY <array-list>) (make-a60:array-decl $1 $3)])
         ;; -------------------- Switches --------------------
         (<switch-list> [(<designational-expression>) (list $1)]
                        [(<switch-list> COMMA <designational-expression>) (append $1 (list $3))])
         (<switch-declaration> [(SWITCH <switch-identifier> ASSIGN <switch-list>) (make-a60:switch-decl $2 $4)])
         ;; -------------------- Procedures --------------------
         (<formal-parameter> [(<identifier>) $1])
         (<formal-parameter-list> [(<formal-parameter>) (list $1)]
                                  [(<formal-parameter-list> <parameter-delimiter> <formal-parameter>) 
                                   (append $1 (list $3))])
         (<formal-parameter-part> [() null]
                                  [(OPEN <formal-parameter-list> CLOSE) $2])
         (<identifier-list> [(<identifier>) (list $1)]
                            [(<identifier-list> COMMA <identifier>) (append $1 (list $3))])
         (<value-part> [(VALUE <identifier-list> SEMICOLON) $2]
                       [() null])
         (<specifier> [(STRING) 'string]
                      [(<type>) $1]
                      [(ARRAY) '(array #f)]
                      [(<type> ARRAY) `(array ,$1)]
                      [(LABEL) 'label]
                      [(SWITCH) 'switch]
                      [(PROCEDURE) '(procedure #f)]
                      [(<type> PROCEDURE) `(procedure ,$1)])
         (<specification-part> [() null]
                               [(<specifier> <identifier-list> SEMICOLON) (list (cons $1 $2))]
                               [(<specification-part> <specifier> <identifier-list>) (append $1 (list (cons $2 $3)))])
         (<procedure-heading> [(<identifier> <formal-parameter-part> SEMICOLON <value-part> <specification-part>)
                               (list $1 $2 $4 $5)])
         (<procedure-body> [(<statement>) $1])
         (<procedure-declaration> [(PROCEDURE <procedure-heading> <procedure-body>)
                                   (make-a60:proc-decl #f (car $2) (cadr $2) (caddr $2) (cadddr $2) $3)]
                                  [(<type> PROCEDURE <procedure-heading> <procedure-body>)
                                   (make-a60:proc-decl $1 (car $3) (cadr $3) (caddr $3) (cadddr $3) $4)])
         ;; ==================== Program ====================
         (<program> [(<block>) $1]
                    [(<compound-statement>) $1]))))
     
     (define-syntax (define-a60-structs stx)
       (syntax-case stx ()
         [(_ (struct-name (field ...)) ...)
          (with-syntax ([(a60:struct ...) (map (lambda (id)
                                                 (string->symbol
                                                  (format "a60:~a" (syntax-e id))))
                                               (syntax->list (syntax (struct-name ...))))])
            (syntax (begin (define-struct a60:struct (field ...)) ...
                           (provide (struct a60:struct (field ...)) ...))))]))
     
     (define-a60-structs
      ;; Expressions
      (if (test then else))
      (unary (op arg))
      (binary (op arg1 arg2))
      (subscript (array index))
      (variable (name indices))
      (app (func args))
      ;; plus numbers, strings, and booleans

      ;; Statements
      (block (decls statements))
      (compound (statements))
      (assign (variables rhs))
      (goto (target))
      (branch (test then else))
      (call (proc args))
      (for (variable values body))
      (dummy ())
      (label (name statement))
      
      ;; for values
      (for-number (value))
      (for-step (start step end))
      (for-while (value test))

      ;; declarations
      (type-decl (type vars))
      (array-decl (type vars))
      (switch-decl (var cases))
      (proc-decl (result-type var arg-vars by-value-vars arg-specs body)))
     
     (define (parse-a60-port port file)
       (let ([buf (make-lex-buf port)]
             [lexer (lexer file)])
         (parse (lambda () 
                  (let loop ()
                    (let ([v (lexer buf)])
                      (if (void? v)
                          (loop)
                          v)))))))
     
     (define (parse-a60-file file)
       (with-input-from-file file
         (lambda ()
           (parse-a60-port (current-input-port)
                           (path->complete-path file)))))

      (provide parse-a60-file parse-a60-port))
   