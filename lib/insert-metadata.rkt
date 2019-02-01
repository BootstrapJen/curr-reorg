":";exec racket -f $0 -m -- "$@"

(define (read-word i)
  (let loop ((r '()))
    (let ((c (peek-char i)))
      (if (char-alphabetic? c)
          (loop (cons (read-char i) r))
          (if (null? r) ""
              (list->string (reverse r)))))))

(define (read-group i)
  (let ((c (peek-char i)))
    (cond ((char=? c #\{)
           (read-char i)
           (let loop ((r '()) (in-space? #t))
             (let ((c (read-char i)))
               (cond ((member c '(#\space #\tab #\newline #\return))
                      (loop (if in-space? r (cons #\space r)) #t))
                     ((char=? c #\})
                      (string-trim (list->string (reverse r))))
                     (else (loop (cons c r) #f))))))
          (else
            (printf "Ill-formed metadata directive~%")
            ""))))

(define (assoc-glossary term L)
  ;(printf "doing assoc-glossary ~s ~n" term)
  (let ((naive-singular (if (char-ci=? (string-ref term (- (string-length term) 1)) #\s)
                             (substring term 0 (- (string-length term) 1))
                             "")))
    ;(printf "naive sing = ~s~n" naive-singular)
    (let loop ((L L))
      (if (null? L) #f
          (let* ((c (car L))
                 (lhs (car c)))
            ;(printf "lhs = ~s~n" lhs)
            (or (cond ((string? lhs)
                       (and (or (string-ci=? lhs term)
                                (string-ci=? lhs naive-singular))
                            c))
                      ((list? lhs)
                       (and (memf (lambda (x) (string-ci=? x term)) lhs)
                            (list (car lhs) (cadr c))))
                      (else #f))
                (loop (cdr L))))))))

(define (check-first-subsection i o)
  (let ((c (peek-char i)))
    (if (char=? c #\=)
        (begin (read-char i)
               (set! c (peek-char i))
               (if (char=? c #\=)
                   #t
                   (begin (display #\= o)
                          #f)))
        #f)))

(define (add-include-directive i o in-file)
  (display "include::" o)
  (display (path-replace-extension in-file "-glossary.adoc3") o)
  (display "[]" o)
  (newline o) (newline o)
  (display #\= o))

(define *summary-file* #f)

(define *all-glossary-items* '())

(define *glossary-list* '())

(define *macro-list* '())

(define *asciidoctor* "asciidoctor -a linkcss -a stylesheet=curriculum.css")

(define (insert-metadata in-file)
  (let ((out-file (path-replace-extension in-file ".adoc2"))
        (glossary-out-file (path-replace-extension in-file "-glossary.adoc3"))
        (glossary-items '())
        ;(standards-file "standards.rkt")
        ;(materials '())
        ;(preparation-items '())
        (first-subsection-crossed? #f)
        )
    (call-with-input-file in-file
      (lambda (i)
        (call-with-output-file out-file
          (lambda (o)
            (let loop ()
              (let ((c (read-char i)))
                (unless (eof-object? c)
                  (case c
                    ((#\@)
                     (let ((directive (read-word i)))
                       ;(printf "directive= ~s~%" directive)
                       (cond ((string=? directive "") (display c o))
                             ((string=? directive "vocab")
                              (let* ((arg (read-group i))
                                     (s (assoc-glossary arg *glossary-list*)))
                                (when (string=? arg "")
                                  (printf "Directive @~a has ill-formed argument~%"
                                          directive))
                                (display arg o)
                                (cond (s
                                        (unless (member s glossary-items)
                                          (set! glossary-items (cons s glossary-items)))
                                        (unless (member s *all-glossary-items*)
                                          (set! *all-glossary-items*
                                            (cons s *all-glossary-items*))))
                                      (else (printf "Item ~a not found in glossary~%"
                                                    arg)))))
                             ((assoc directive *macro-list*) =>
                              (lambda (s)
                                (display (cadr s) o)))
                             (else
                               (printf "Unrecognized directive @~a~%" directive)
                               #f))))
                    ((#\newline)
                     (newline o)
                     (cond (first-subsection-crossed? #f)
                           ((check-first-subsection i o)
                            (set! first-subsection-crossed? #t)
                            (add-include-directive i o in-file))
                           (else #f)))
                    (else (display c o)))
                  (loop)))))
          #:exists 'replace)))
    (set! glossary-items
      (sort glossary-items #:key car string-ci<=?))
    (call-with-output-file glossary-out-file
      (lambda (g)
        (for-each
          (lambda (s)
            (display "* *" g) (display (car s) g) (display "*: " g)
            (display (cadr s) g) (newline g))
          glossary-items))
      #:exists 'replace)
    (system (format "~a ~a" *asciidoctor* out-file))))

(define (main . args)
  (set! *glossary-list* (call-with-input-file "glossary-terms.rkt" read))
  (set! *all-glossary-items* '())
  (set! *summary-file* "summary.adoc2")
  (set! *macro-list* (call-with-input-file "form-elements.rkt" read))
  (for-each insert-metadata args)
  (when (pair? *all-glossary-items*)
    (set! *all-glossary-items*
      (sort *all-glossary-items* #:key car string-ci<=?))
    (call-with-output-file *summary-file*
      (lambda (g)
        (for-each
          (lambda (s)
            (display "* *" g) (display (car s) g) (display "*: " g)
            (display (cadr s) g) (newline g))
          *all-glossary-items*))
      #:exists 'replace)
    (system (format "~a ~a" *asciidoctor* *summary-file*)))
  (void))
