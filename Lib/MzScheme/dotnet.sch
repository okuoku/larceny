;; -*-Mode: Scheme; coding: iso-8859-1 -*-
;; Port of dotnet.ss to larceny

;; NOTE:  This file requires that dotnet-ffi.sch has been loaded.

;;; Snarf these two macros to facilitate bootstrapping.
(define-syntax %set-instance/procedure!
  (syntax-rules ()
    ((%set-instance/procedure! instance proc) (procedure-set! instance 3 proc))))

(define-syntax lookup-slot-info
  (syntax-rules ()
    ((lookup-slot-info class slot-name selector)
     (selector (or (assq slot-name
                         ;; no need to ground slot-ref any more! -- see below
                         ;; (if (eq? class <class>)
                         ;;   ;;* This grounds out the slot-ref tower
                         ;;   getters-n-setters-for-class
                         ;;   (%class-getters-n-setters class))
                         (%class-getters-n-setters class))
                   (error "slot-ref: no slot `~e' in ~e " slot-name class))))))



(define (show name thing)
  (dotnet-message 0 name thing)
  thing)

(define (describe-instance instance)
  (dotnet-message 0 "Description of" instance)
  (for-each (lambda (slot)
              (dotnet-message 0 "slot" (car slot)
                              (if (slot-bound? instance (car slot))
                                  (slot-ref instance (car slot))
                                  "is unbound")))
            (class-slots (class-of instance)))
  (dotnet-message 0 "End description"))

(define (void)
  (if #f #f))

(define (void? thing) (eq? thing (void)))
(define (flush-output) #f)

;;; End of miscellany

;;; End of primitive accessors

(define clr/default-marshal-out (make (*default-generic-class*) :arity 1 :name 'clr/default-marshal-out))

(add-method clr/default-marshal-out
  (make (*default-method-class*)
    :arity 1
    :specializers (list <exact-integer>)
    :procedure (lambda (call-next-method number)
                 (clr/%number->foreign-int32 number))))

(add-method clr/default-marshal-out
  (make (*default-method-class*)
    :arity 1
    :specializers (list <string>)
    :procedure (lambda (call-next-method string)
                 (clr/%string->foreign string))))

(add-method clr/default-marshal-out
  (make (*default-method-class*)
    :arity 1
    :specializers (list <procedure>)
    :procedure (lambda (call-next-method proc)
                 (clr/%schemeobject->foreign proc))))

;;;; .NET Class hierarchy

;; The class hierarchy in Scheme will mirror the .NET class hierarchy.
;; This requires just a couple of bits of magic, that once performed,
;; will allow the rest of the .NET class structure to be generated on
;; the fly through the MOP.

;; In .NET, every .NET object is an instance of a System.Object
;; In the Scheme world, the CLASS-OF function is exactly analagous to
;; GetType.

;; So in Scheme, we want all .NET objects to be instances of a
;; System.Object class.  All Scheme System.Object instances have a
;; com-object slot that holds the COM wrapper to the .NET class.

;; Every .NET object has a type, and the GetType method on
;; System.Object returns that type.  Since a type object is *also* a
;; .NET object, it *also* has a type.  There is a distinguished type
;; that is the fixed-point of GetType and all .NET types inherit from
;; it.  Note that this implies that this distinguished type *is an
;; instance of itself* (so much for the single inheritance myth).

  ;; Don't think I need to export these names.
  ;; (provide System.RuntimeType System.Object)

  ;; Given a StudlyName string, return an appropriate key for the
  ;; various hash tables.
(define (StudlyName->key StudlyName)
;    (parameterize ((read-square-bracket-as-paren #f)
;                   (read-case-sensitive #f))
;      (read-from-string StudlyName)))
    (string->symbol (string-downcase StudlyName))
    )

  ;; A temporary scaffolding class for bootstrapping
  ;; the .NET class hierarchy.
;  (defclass <class-with-com-object-scaffold> (<class>)
;    (com-object :initarg :com-object))

(define <class-with-clr-object-scaffold>
  (begin
    (if (*make-safely*)
        (check-initargs
         (*default-class-class*)
         (list :direct-default-initargs #f
               :direct-supers (list <class>)
               :direct-slots (list (list 'clr-handle :initarg :clr-handle))
               :name '<class-with-clr-object-scaffold>)))
    (let ((<class-with-clr-object-scaffold>
           (rec-allocate-instance
            (*default-class-class*)
            (list :direct-default-initargs #f
                  :direct-supers (list <class>)
                  :direct-slots (list (list 'clr-handle :initarg :clr-handle))
                  :name '<class-with-clr-object-scaffold>))))
      (rec-initialize <class-with-clr-object-scaffold>
                      (list :direct-default-initargs #f
                            :direct-supers (list <class>)
                            :direct-slots (list (list 'clr-handle :initarg :clr-handle))
                            :name '<class-with-clr-object-scaffold>))
      <class-with-clr-object-scaffold>)))

(add-method allocate-instance
  (make <method>
    :arity 2
    :specializers (list (singleton <class-with-clr-object-scaffold>))
    :qualifier :primary
    :procedure ((lambda ()
                  (define (method:allocate-instance call-next-method class initargs)
                    (%make-instance class
                                    (make-vector (+ (length (%class-field-initializers class))
                                                    (length (getarg initargs :direct-slots '())))
                                                 (undefined))))
                  method:allocate-instance))))

  ;; System.RuntimeType will be one root of the metaclass hierarchy.
  ;; Every .NET type object will inherit from this class, including
  ;; the instance that represents this class!
;  (defclass System.RuntimeType (<class-with-clr-object-scaffold>)
;    (StudlyName :initarg :StudlyName :reader clr/StudlyName)
;    :metaclass <class-with-clr-object-scaffold>)

(define System.RuntimeType
  (begin
    (if (*make-safely*)
        (check-initargs
         <class-with-clr-object-scaffold>
         (list :direct-default-initargs #f
               :direct-supers (list <class-with-clr-object-scaffold>)
               :direct-slots
               (list
                (list 'can-instantiate? :initarg :can-instantiate? :reader 'clr-class/can-instantiate?)
                (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName)
                (list 'argument-marshaler :initarg :argument-marshaler :reader 'argument-marshaler)
                (list 'return-marshaler :initarg :return-marshaler :reader 'return-marshaler))

               :name 'System.RuntimeType)))
    (let ((System.RuntimeType
           (rec-allocate-instance
            <class-with-clr-object-scaffold>
            (list :direct-default-initargs #f
                  :direct-supers (list <class-with-clr-object-scaffold>)
                  :direct-slots
                  (list
                   (list 'can-instantiate? :initarg :can-instantiate? :reader 'clr-class/can-instantiate?)
                   (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName)
                   (list 'argument-marshaler :initarg :argument-marshaler :reader 'argument-marshaler)
                   (list 'return-marshaler :initarg :return-marshaler :reader 'return-marshaler))
                  :name 'System.RuntimeType))))
      (rec-initialize
       System.RuntimeType
       (list :direct-default-initargs #f
             :direct-supers (list <class-with-clr-object-scaffold>)
             :direct-slots
             (list
              (list 'can-instantiate? :initarg :can-instantiate? :reader 'clr-class/can-instantiate?)
              (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName)
              (list 'argument-marshaler :initarg :argument-marshaler :reader 'argument-marshaler)
              (list 'return-marshaler :initarg :return-marshaler :reader 'return-marshaler))
             :name 'System.RuntimeType))
      System.RuntimeType)))

(define clr/StudlyName (make (*default-generic-class*) :name 'clr/StudlyName))

(add-method clr/StudlyName
 (make (*default-method-class*)
   :arity 1
   :specializers (list System.RuntimeType)
   :procedure (lambda (call-next-method x) (slot-ref x 'StudlyName))))

;; (argument-marshaler type) =>   procedure from instance to ffi object
(define argument-marshaler (make (*default-generic-class*) :name 'argument-marshaler))

(add-method argument-marshaler
  (make (*default-method-class*)
    :arity 1
    :specializers (list System.RuntimeType)
    :procedure (lambda (call-next-method type)
                 (slot-ref type 'argument-marshaler))))

;; (argument-specializer type) => class
(define argument-specializer (make (*default-generic-class*) :name 'argument-specializer))

;; Temporary definition.
(add-method argument-specializer
  (make (*default-method-class*)
    :arity 1
    :specializers (list System.RuntimeType)
    :procedure (lambda (call-next-method type) type)))

(define return-marshaler (make (*default-generic-class*) :name 'return-marshaler))

;; (return-marshaler type) => procedure from ffi object to instance
(add-method return-marshaler
  (make (*default-method-class*)
    :arity 1
    :specializers (list System.RuntimeType)
    :procedure (lambda (call-next-method type)
                 (slot-ref type 'return-marshaler))))

(define (clr-class/can-instantiate? runtime-type)
  (slot-ref runtime-type 'can-instantiate?))

;;; This starts out #f.  As classes are instantiated, we put them on
;;; the list of *delayed-initialized* until we can turn on
;;; auto-initialization.
(define *auto-initialize* #f)
(define *delayed-initialized* '())

(define (initialize-instance-members! runtime-type)
  (dotnet-message 2 "Initialize instance members of" runtime-type)
  (clr-class/for-selected-members
   process-public-member runtime-type
   (list
    ;; already done
    ;; clr-member-type/constructor
    clr-member-type/event
    clr-member-type/field
    clr-member-type/method
    clr-member-type/property
    clr-member-type/type-info
    clr-member-type/custom
    clr-member-type/nested-type)
   #f #t)
  (clr-class/for-selected-members
   process-private-member runtime-type
   (list
    ;; already done
    ;; clr-member-type/constructor
    clr-member-type/event
    clr-member-type/field
    clr-member-type/method
    clr-member-type/property
    clr-member-type/type-info
    clr-member-type/custom
    clr-member-type/nested-type)
   #f #f))

(define (initialize-static-members! runtime-type)
  (dotnet-message 2 "Initialize static members of" runtime-type)
  (clr-class/for-selected-members
   process-public-member runtime-type
   (list
    clr-member-type/constructor
    clr-member-type/event
    clr-member-type/field
    clr-member-type/method
    clr-member-type/property
    clr-member-type/type-info
    clr-member-type/custom
    clr-member-type/nested-type)
   #t #t)

  (clr-class/for-selected-members
   process-private-member runtime-type
   (list
    clr-member-type/constructor
    clr-member-type/event
    clr-member-type/field
    clr-member-type/method
    clr-member-type/property
    clr-member-type/type-info
    clr-member-type/custom
    clr-member-type/nested-type)
   #t #f)

  ;; Have to do constructors, which are instance methods?!
  (clr-class/for-selected-members
   (lambda (constructor member-type)
     (install-constructor constructor #t))
   runtime-type
   (list clr-member-type/constructor) #f #t)

  (clr-class/for-selected-members
   (lambda (constructor member-type)
     (install-constructor constructor #f))
   runtime-type
   (list clr-member-type/constructor) #f #t))

(define (clr-class/ensure-instantiable! runtime-type)
  (or (clr-class/can-instantiate? runtime-type)
      (begin
        (dotnet-message 3 "Making class instantiable" runtime-type)
        (let ((base-type (clr-type/%base-type
                          (clr-object/clr-handle runtime-type))))
          (if (and base-type
                   (not (null? base-type))
                   (not (void? base-type))
                   (not (clr/%null? base-type)))
              (clr-class/ensure-instantiable! (clr-object->class base-type))))
        (if *auto-initialize*
            (initialize-instance-members! runtime-type)
            (set! *delayed-initialized*
                  (cons runtime-type *delayed-initialized*)))
        (slot-set! runtime-type 'can-instantiate? #t))))

(define (enable-auto-initialization!)
  (set! *auto-initialize* #t)
  (for-each clr-class/ensure-instantiable! *delayed-initialized*)
  (set! *delayed-initialized* '()))

;; A hash table mapping symbols to the Ripoff classes that
;; represent .NET classes.  The symbolic key will simply be the
;; name of the class as a case-folded symbol.
(define *clr-type-table* (make-hash-table 'symbol-eq?))

(define (register-dotnet-class! StudlyName class)
  (hash-table-put! *clr-type-table* (StudlyName->key StudlyName) class))

(define (map-dotnet-classes function)
  (hash-table-map *clr-type-table* (lambda (key value) (function value))))

;; This :after method ensures that any classes we create
;; will be installed in the *clr-type-table*
;; We specialize the ALLOCATE-INSTANCE method rather than the
;; INITIALIZE-INSTANCE method so that initialization will be allowed to refer
;; to the uninitialized class object.  (This is so methods created
;; at the time the time the class is created can refer to the type.)
;; Note use of :around method so we can get the return value of allocate-instance.
;; Note use of singleton is required for allocate instance because the
;; instance itself does not yet exist.

;  (defmethod :around (allocate-instance class initargs)
;    ;; Bug in Swindle prevents use of singleton class.
;    (if (eq? class System.RuntimeType)
;        (let ((instance (call-next-method))
;              (StudlyName (getarg initargs :StudlyName)))
;          ;; (dotnet-message "Class" StudlyName)
;          (register-dotnet-class! StudlyName instance)
;          instance)
;        (call-next-method)))

(define max-arity (make (*default-generic-class*) :name 'max-arity))


;; (clr-object/clr-handle instance) => handle
(define clr-object/clr-handle (make (*default-generic-class*) :name 'clr-object/clr-handle))


(define <clr-generic>
  (begin
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list
          :direct-default-initargs #f
          :direct-supers (list <generic>)
          :direct-slots (list
                              (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName))
          :name '<clr-generic>)))
    (let ((<clr-generic>
           (rec-allocate-instance
            (*default-entityclass-class*)
            (list
             :direct-default-initargs #f
             :direct-supers (list <generic>)
             :direct-slots (list
                            (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName))
             :name '<clr-generic>))))
      (rec-initialize
       <clr-generic>
       (list
        :direct-default-initargs #f
        :direct-supers (list <generic>)
        :direct-slots (list
                            (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName))
        :name '<clr-generic>))
      <clr-generic>)))

(add-method clr/StudlyName
  (make (*default-method-class*)
    :specializers (list <clr-generic>)
    :arity 1
    :procedure (lambda (call-next-method x) (slot-ref x 'StudlyName))))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-generic>)
    :arity 3
    :procedure ((lambda ()
                 (define (print-object call-next-method object port slashify)
                     (display "#<CLR-GENERIC " port)
                     (display (generic-arity object) port)
                     (display " " port)
                     (display (clr/StudlyName object) port)
                     (display ">" port))
                 print-object))))

(define <clr-arity-overload>
  (begin
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list
          :direct-default-initargs '() ;; (list :arity (make-arity-at-least 1))
          :direct-supers (list <clr-generic>)
          :direct-slots (list (list 'arity-vector :initarg :arity-vector))
          :name '<clr-arity-overload>)))

    (let ((<clr-arity-overload>
           (rec-allocate-instance
            (*default-entityclass-class*)
            (list
             :direct-default-initargs '() ;; (list :arity (make-arity-at-least 1))
             :direct-supers (list <clr-generic>)
             :direct-slots (list (list 'arity-vector :initarg :arity-vector))
             :name '<clr-arity-overload>))))
      (rec-initialize
       <clr-arity-overload>
       (list
        :direct-default-initargs '() ;; (list :arity (make-arity-at-least 1))
        :direct-supers (list <clr-generic>)
        :direct-slots (list (list 'arity-vector :initarg :arity-vector))
        :name '<clr-arity-overload>))
      <clr-arity-overload>)))

(define get-arity-vector
  (lookup-slot-info <clr-arity-overload> 'arity-vector cadr))

(add-method initialize-instance
  (make (*default-method-class*)
    :arity 2
    :specializers (list <clr-arity-overload>)
    :procedure (lambda (call-next-method generic initargs)
                 (dotnet-message 4 "Overloading" (clr/StudlyName generic))
                 (add-method
                   generic
                   (make (*default-method-class*)
                     :arity (make-arity-at-least 0)
                     :specializers (list <top>)
                     :procedure (lambda (call-next-method . arguments)
                                  (let ((argcount (length arguments)))
                                    (let ((vector (get-arity-vector generic)))
                                      (if (not (< argcount (vector-length vector)))
                                          (error "Too many arguments to overloaded method. "
                                                 generic
                                                 argcount)
                                          (let ((target (vector-ref vector argcount)))
                                            (if (instance-of? target <clr-generic>)
                                                (apply target arguments)
                                                (error "No overloaded method for "
                                                       arguments))))))))))
    :qualifier :after))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-arity-overload>)
    :arity 3
    :procedure ((lambda ()
                 (define (print-object call-next-method object port slashify)
                     (display "#<CLR-OVERLOAD " port)
                     (display (clr/StudlyName object) port)
                     (display ">" port))
                 print-object))))

(define (ensure-overload-vector-capacity overload desired-maximum-arity)
  (let* ((vector (get-arity-vector overload))
         (capacity (vector-length vector)))
    (if (<= capacity desired-maximum-arity)
        (begin
          ;; copy the elements
          (let loop ((new-vector (make-vector (+ desired-maximum-arity 1) #f))
                     (index 0))
            (if (= index capacity)
                (slot-set! overload 'arity-vector new-vector)
                (begin (vector-set! new-vector index
                                    (vector-ref vector index))
                       (loop new-vector (+ index 1)))))))))

;; (wrap-clr-object wrapper-class handle) => instance
;; Create an instance of a CLR class to represent the .NET object
(define wrap-clr-object (make (*default-generic-class*) :name 'wrap-clr-object))

;; (clr-object->class handle-to-clr-type) => class

;; The CLR-TYPE-DESCRIPTOR is a .NET Type
;; We extract the name of the type and look it up in the *clr-type-table*
;; to get the Scheme class that represents the type.
;;
;; If the type isn't in the table yet, we create it on the fly by
;; recursively locating the parent type and creating a instance of a
;; <clr-class> to represent the new type (which will register it in the
;; table).  This bottoms out when we get to System.RuntimeType which
;; is manually created.
(define (clr-object->class clr-type-descriptor)
  (let* ((StudlyName    (clr/%to-string clr-type-descriptor))
         (clr-type-name (StudlyName->key StudlyName)))
    (dotnet-message 4 "CLR-OBJECT->CLASS: " StudlyName)
    (hash-table-get
     *clr-type-table* clr-type-name
     (lambda ()
       ;; (dotnet-message "Instantiating class object of type"
       ;;                 (clr/%to-string (clr/%object-type clr-type-descriptor))
       ;;                 "for" StudlyName)
       ;; Not found?  Create one.
       (letrec ((descriptor
                 (make (clr-object->class (clr/%object-type clr-type-descriptor))
                   :name clr-type-name
                   :StudlyName StudlyName
                   :clr-handle clr-type-descriptor
                   :direct-supers
                   (append (map-clr-array clr-object->class
                                          (clr-type/%get-interfaces clr-type-descriptor))
                           ;; As it turns out, the "BaseType" property is *not* a reliable
                           ;; means to figure out the base type.  This COND special cases the
                           ;; known problems.
                           (let ((bt-property (clr-type/%base-type clr-type-descriptor)))
                             (if (or (not bt-property)
                                     (null? bt-property)
                                     (void? bt-property)
                                     (clr/%null? bt-property))
                                 (list System.Object)
                                 (list (clr-object->class bt-property)))))
                   :can-instantiate? #f
                   :argument-marshaler clr-object/clr-handle
                   :return-marshaler (lambda (instance)
                                       (if (clr/%null? instance)
                                           '()
                                           (wrap-clr-object descriptor instance))))))
         descriptor)))))

;; Specifically check for Type so we don't create multiple wrappers.
(add-method wrap-clr-object
  (make (*default-method-class*)
    :arity 2
    :specializers (list (singleton System.RuntimeType))
    :procedure (lambda (call-next-method class object)
                 (clr-object->class object))))

;; For the most part, we can simply instantiate the wrapper.
(add-method wrap-clr-object
  (make (*default-method-class*)
    :arity 2
    :specializers (list System.RuntimeType)
    :procedure (lambda (call-next-method class object)
                 (make class :clr-handle object))))

(define (clr/default-marshal-in object)
  (cond ((eq? object (unspecified)) object)
        ((%clr-array? object)
         (list->vector (map-clr-array clr/default-marshal-in object)))
        ((%clr-enum? object) (clr/%foreign->int object))
        ((%clr-int32? object) (clr/%foreign->int object))
        ((%clr-string? object) (clr/foreign->string object))
        ((clr/%null? object) '())
        ((clr/%eq? object clr/true) #t)
        ((clr/%eq? object clr/false) #f)
        (else (clr-object->clr-instance object))))

  ;; System.Object will be the root of the class hierarchy.
  ;; Every .NET class will inherit from this class.
  ;; Every COM object that represents a .NET object will inherit from this one.
  ;; (Note: don't try to create a superclass for this, it won't work.
  ;;   -- the voice of experience)

(define System.Object
  (begin
    (if (*make-safely*)
        (check-initargs
         System.RuntimeType
         (list :StudlyName "System.Object"
               :clr-handle clr-type-handle/system-object
               :direct-default-initargs #f
               :direct-supers (list <object>)
               :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle))
               :name 'system.object)))
    (let ((System.Object
           (rec-allocate-instance
            System.RuntimeType
            (list :StudlyName "System.Object"
                  :clr-handle clr-type-handle/system-object
                  :direct-default-initargs #f
                  :direct-supers (list <object>)
                  :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle))
                  :name 'system.object))))
      (rec-initialize
       System.Object
       (list :StudlyName "System.Object"
             :clr-handle clr-type-handle/system-object
             :direct-default-initargs #f
             :direct-supers (list <object>)
             :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle))
             :can-instantiate? #f
             :argument-marshaler clr/default-marshal-out
             :return-marshaler clr/default-marshal-in
             :name 'system.object))
      System.Object)))

(add-method clr-object/clr-handle
  (make (*default-method-class*)
    :arity 1
    :specializers (list System.Object)
    :procedure (lambda (call-next-method instance)
                 (slot-ref instance 'clr-handle))))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list System.Object)
    :arity 3
    :procedure ((lambda ()
                  (define (print-object call-next-method object port slashify)
                    (let* ((clr-object  (clr-object/clr-handle object))
                           (type-name   (clr/%to-string (clr-object/clr-handle (class-of object))))
                           (printed-rep (clr/%to-string clr-object)))

                      (display "#<" port)
                      (display type-name port)
                      (if (not (string=? type-name printed-rep))
                          (begin
                            (display " " port)
                            (display printed-rep port)))
                      (if (assq 'arity (class-slots (class-of object)))
                          (begin
                            (display " " port)
                            (display (slot-ref object 'arity) port)))
                      (display ">" port)))
                  print-object))))

;; Widen system.object to include everything
;; so we can pass ints, strings, etc.
(add-method argument-specializer
  (make (*default-method-class*)
    :arity 1
    :specializers (list (singleton System.Object))
    :procedure (lambda (call-next-method x) <top>)))

(add-method clr/default-marshal-out
  (make (*default-method-class*)
    :arity 1
    :specializers (list System.Object)
    :procedure (lambda (call-next-method instance)
                 (clr-object/clr-handle instance))))

(define (setup-type-type bootstrap-clr-object)
  ;; The classes defined above are isomorphic to what we want, so we
  ;; simply need to kick out the supporting structure.

  ;; Get the type descriptor of the type class
  ;; by finding the fixed point of GetType.
  (let loop ((this bootstrap-clr-object)
             (previous-name ""))
    (let* ((this-type (clr/%object-type this))
           (this-name (clr/%to-string this-type)))
      (dotnet-message 5 "This name:  " this-name "Previous name:  " previous-name)
      (if (string=? this-name previous-name)
          ;; Got it.
          (let ((type-type this-type))

            ;; Set up the System.RuntimeType to be an instance
            ;; of itself (using some magic).  This *must* be done first
            ;; so that any clases created on demand while we initialize
            ;; will have the correct inheritance chain.
            ;; (dotnet-message "set-instance-class-to-self!")
            (set-instance-class-to-self! System.RuntimeType)

            ;; Set the clr-object slot and put this class in the
            ;; type table.
            ;; (dotnet-message "slot-set System.RuntimeType 'clr-handle")
            (slot-set! System.RuntimeType 'clr-handle type-type)
            ;; (dotnet-message "slot-set System.RuntimeType 'studlyname")
            (slot-set! System.RuntimeType 'StudlyName this-name)
            ;; (dotnet-message "register dotnet class")
            (register-dotnet-class! "System.Object" System.Object)
            (register-dotnet-class! this-name System.RuntimeType)

            ;; Arrange for class instances to registered prior to
            ;; initialization.
            (add-method allocate-instance
              (make (*default-method-class*)
                :specializers (list (singleton System.RuntimeType))
                :arity 2
                :qualifier :primary
                :procedure ((lambda ()
                              (define (allocate-runtime-type call-next-method class initargs)
                                (let ((instance (call-next-method))
                                      (StudlyName (or (getarg initargs :StudlyName #f)
                                                      (error "Required initarg :StudlyName omitted"))))
                                  (dotnet-message 1 "Register class" StudlyName)
                                  (register-dotnet-class! StudlyName instance)
                                  (add-method allocate-instance
                                    (make (*default-method-class*)
                                      :arity 2
                                      :specializers (list (singleton instance))
                                      :qualifier :before
                                      :procedure
                                      ((lambda ()
                                         (define (allocate call-next-method class initargs)
                                           (clr-class/ensure-instantiable! class))
                                         allocate))))
                                  instance))
                              allocate-runtime-type))))

            ;; Reset the direct supers of the type class to be the correct object
            ;; and recompute the class precedence list and slots.  Once this is done,
            ;; we are bootstrapped.

            ;; Note that call to CLR-OBJECT->CLASS will cause other classes to be loaded.
            ;; This is ok because enough of System.RuntimeType is initialized to
            ;; make subsequent type creation work.
            ;; (dotnet-message (clr-type/%base-type this-type))
            ;; (dotnet-message (clr-object->class (clr-type/%base-type this-type)))

            (slot-set! System.RuntimeType 'direct-supers
                       (append (cons (clr-object->class (clr-type/%base-type type-type))
                                     (map-clr-array clr-object->class
                                                    (clr-type/%get-interfaces type-type)))
                               (list <class>)))
            (slot-set! System.RuntimeType 'cpl   (compute-cpl System.RuntimeType))
            (slot-set! System.RuntimeType 'slots (compute-slots System.RuntimeType))
            (slot-set! System.RuntimeType 'can-instantiate? #f)
            (slot-set! System.RuntimeType 'argument-marshaler   clr-object/clr-handle)
            (slot-set! System.RuntimeType 'return-marshaler     clr-object->class)
            (set! *delayed-initialized* (cons System.RuntimeType *delayed-initialized*))

            ;; Optimize the getter for the handle
            (add-method clr-object/clr-handle
              (make (*default-method-class*)
                :arity 1
                :specializers (list System.RuntimeType)
                :procedure (let ((getter (lookup-slot-info System.RuntimeType 'clr-handle cadr)))
                             (lambda (call-next-method instance)
                               (getter instance))))))

          (loop this-type this-name)))))

(define (setup-system-object)
  ;; Now we need to find the type object associated with System.Object.
  ;; This time we walk the type hierarchy in `BaseType' direction.
  (dotnet-message 4 "Setup system object")
  (let loop ((this (slot-ref System.RuntimeType 'clr-handle)))
    (let ((this-name (clr/%to-string this)))
      (if (string=? this-name "System.Object")
          ;; Should only be true when bootstrapping.
          ;; The type will be in the hash table after that.
          (slot-set! System.Object 'clr-handle this)
          (loop (clr-type/%base-type this))))))

;; Handle certain reflected objects specially to integrate them into
;; the Scheme type system.
(define (setup-reflection)
  (for-each (lambda (handle builtin)
              (add-method argument-specializer
                (make (*default-method-class*)
                  :arity 1
                  :specializers (list (singleton (clr-object->class handle)))
                  :procedure (lambda (call-next-method instance) builtin))))
            (list clr-type-handle/system-char
                  clr-type-handle/system-boolean
                  clr-type-handle/system-int32
                  clr-type-handle/system-string)
            (list <char>
                  <boolean>
                  <exact-integer>
                  <string>))

  (let ((int-class (clr-object->class clr-type-handle/system-int32)))
    (slot-set! int-class 'argument-marshaler clr/int->foreign)
    (slot-set! int-class 'return-marshaler clr/foreign->int))

  (let ((bool-class (clr-object->class clr-type-handle/system-boolean)))
    (slot-set! bool-class 'argument-marshaler clr/bool->foreign)
    (slot-set! bool-class 'return-marshaler   clr/foreign->bool))

  (let ((string-class (clr-object->class clr-type-handle/system-string)))
    (slot-set! string-class 'argument-marshaler clr/string->foreign)
    (slot-set! string-class 'return-marshaler   clr/foreign->string))

  (let ((system-type-class (clr-object->class clr-type-handle/system-type)))
    (slot-set! system-type-class 'return-marshaler
               (lambda (instance)
                 (if (clr/%null? instance)
                     '()
                     (begin
                       ;; Before wrapping, import the runtime type if necessary.
                       (hash-table-get
                        *clr-type-table* (StudlyName->key (clr/%to-string instance))
                        (lambda ()
                          (clr-object->class
                           (clr-assembly/%get-type
                            (clr-type/%assembly instance)
                            (clr/%string->foreign
                             (clr/%to-string instance))))))
                       ;; wrap the object
                       (wrap-clr-object system-type-class instance))))))

  (let ((void-class (clr-object->class clr-type-handle/system-void)))
    (slot-set! void-class 'argument-marshaler (lambda (x) (error "Cannot marshal void.")))
    (add-method argument-specializer
      (make (*default-method-class*)
        :arity 1
        :specializers (list (singleton void-class))
        :procedure (lambda (call-next-method instance)
                     (error "Cannot specialize on void argument"))))
    (slot-set! void-class 'return-marshaler (lambda (ignore) (unspecified))))

  (for-each (lambda (handle)
              (let ((class (clr-object->class handle)))
                (slot-set! class 'argument-marshaler clr/int->foreign)
                (slot-set! class 'return-marshaler   clr/foreign->int)))

            (list clr-type-handle/system-byte
                  clr-type-handle/system-int16
                  clr-type-handle/system-int64
                  clr-type-handle/system-uint16
                  clr-type-handle/system-uint32
                  clr-type-handle/system-uint64
                  clr-type-handle/system-sbyte))

  (let ((array-class
         (make (clr-object->class (clr/%object-type clr-type-handle/system-array))
           :name (StudlyName->key (clr/%to-string clr-type-handle/system-array))
           :StudlyName (clr/%to-string clr-type-handle/system-array)
           :clr-handle clr-type-handle/system-array
           :direct-supers (cons (clr-object->class (clr-type/%base-type clr-type-handle/system-array))
                                (map-clr-array clr-object->class
                                               (clr-type/%get-interfaces clr-type-handle/system-array)))
           :direct-slots '()
           :can-instantiate? #f
           :argument-marshaler clr-object/clr-handle
           :return-marshaler clr-object->class))

        (enum-class
         (make (clr-object->class (clr/%object-type clr-type-handle/system-enum))
           :name (StudlyName->key (clr/%to-string clr-type-handle/system-enum))
           :StudlyName (clr/%to-string clr-type-handle/system-enum)
           :clr-handle clr-type-handle/system-enum
           :direct-supers (cons (clr-object->class (clr-type/%base-type clr-type-handle/system-enum))
                                (map-clr-array clr-object->class
                                               (clr-type/%get-interfaces clr-type-handle/system-enum)))
           :direct-slots (list (list 'StudlyName :initarg :StudlyName :reader 'clr/StudlyName)
                               (list 'enumerates :allocation :class :reader 'enum/enumerates)
                               (list 'value      :initarg :value :reader 'enum/value))
           :can-instantiate? #f
           :argument-marshaler clr-object/clr-handle
           :return-marshaler clr-object->class))

        (methodbase-class
         (make (clr-object->class (clr/%object-type clr-type-handle/system-reflection-methodbase))
           :name (StudlyName->key (clr/%to-string clr-type-handle/system-reflection-methodbase))
           :StudlyName (clr/%to-string clr-type-handle/system-reflection-methodbase)
           :clr-handle clr-type-handle/system-reflection-methodbase
           :direct-supers (list* <method>
                                (clr-object->class
                                 (clr-type/%base-type clr-type-handle/system-reflection-methodbase))
                                (map-clr-array clr-object->class
                                               (clr-type/%get-interfaces
                                                clr-type-handle/system-reflection-methodbase)))
           :direct-slots  (list (list 'max-arity :initarg :max-arity :reader 'max-arity))
           :can-instantiate? #f
           :argument-marshaler clr-object/clr-handle))

        )

    (slot-set! methodbase-class 'return-marshaler (lambda (object)
                                                    (if (clr/%null? object)
                                                        '()
                                                        (wrap-clr-object methodbase-class object))))

    (add-method argument-specializer
      (make (*default-method-class*)
        :arity 1
        :specializers (list System.RuntimeType)
        :procedure (lambda (call-next-method type)
                     (cond ((subclass? type array-class) <vector>)
                           ((and (subclass? type enum-class)
                                 (memq '|System.FlagsAttribute| (clr-type/get-custom-attributes
                                                                 (clr-object/clr-handle type))))
                            <list>)
                           (else type)))))

    (add-method max-arity
      (make (*default-method-class*)
        :arity 1
        :specializers (list methodbase-class)
        :procedure (lambda (call-next-method x)
                     (slot-ref x 'max-arity))))

    (add-method initialize-instance
      (make (*default-method-class*)
        :arity 2
        :specializers (list System.RuntimeType)
        :procedure (lambda (call-next-method instance initargs)
                     (call-next-method)
                     (if (subclass? instance methodbase-class)
                         (add-method wrap-clr-object
                           (make (*default-method-class*)
                             :arity 2
                             :specializers (list (singleton instance))
                             :procedure (lambda (call-next-method class object)
                                          (clr-object->method class object)))))
                     (if (subclass? instance enum-class)
                         (initialize-enum-class instance))
                     (if (subclass? instance array-class)
                         (initialize-array-class instance))
                     )))

    (add-method initialize-instance
      (make (*default-method-class*)
        :arity 2
        :specializers (list methodbase-class)
        :procedure (lambda (call-next-method instance initargs)
                     (call-next-method)
                     (process-method-or-constructor
                      instance
                      (clr-methodbase/is-public?
                       (clr-object/clr-handle instance))))))

    ))

(define (marshal-vector->array array-class)
  (define (vector->clr-array vector)
    (error "marshal-vector->array" array-class vector))
  vector->clr-array)

(define (marshal-array->vector array-class)
  (dotnet-message 4 "Marshal-array->vector" array-class)
  (let ((element-marshaler (return-marshaler
                            (clr/find-class
                             (string->symbol
                             (clr/%to-string
                              (clr-type/%get-element-type
                               (clr-object/clr-handle array-class))))))))
    (define (clr-array->vector array)
      (if (clr/%null? array)
          '()
          (list->vector (map-clr-array element-marshaler array))))
    clr-array->vector))

(define (initialize-array-class array-class)
  ;; (dotnet-message "Initialize array class" array-class)
  (slot-set! array-class 'argument-marshaler (marshal-vector->array array-class))
  (slot-set! array-class 'return-marshaler (marshal-array->vector array-class)))

(define enum/has-flags-attribute? (make (*default-generic-class*) :name 'enum/has-flags-attribute?))
(define enum/enumerates (make (*default-generic-class*) :name 'enum/enumerates))
(define enum/value (make (*default-generic-class*) :name 'enum/value))

(define (initialize-enum-class enum-class)
  (dotnet-message 3 "Initialize enum class" enum-class)
  (let* ((handle     (clr-object/clr-handle enum-class))
         (flag?      (memq '|System.FlagsAttribute| (clr-type/get-custom-attributes handle)))
         (names      (clr-enum/get-names handle))
         (vals       (clr-enum/get-values handle)))

    (add-method enum/has-flags-attribute?
      (make (*default-method-class*)
        :arity 1
        :specializers (list (singleton enum-class))
        :procedure (lambda (call-next-method class)
                     flag?)))

    (add-method print-object
      (make (*default-method-class*)
        :arity 3
        :specializers (list enum-class)
        :procedure ((lambda ()
                      (define (print-object call-next-method object port slashify)
                        (display "#<" port)
                        (display (clr/StudlyName enum-class) port)
                        (display " " port)
                        (display (clr/StudlyName object) port)
                        (display ">" port))
                      print-object))))

    (add-method clr/StudlyName
      (make (*default-method-class*)
        :arity 1
        :specializers (list enum-class)
        :procedure (lambda (call-next-method instance)
                     (slot-ref instance 'StudlyName))))

    (add-method enum/value
      (make (*default-method-class*)
        :arity 1
        :specializers (list enum-class)
        :procedure (lambda (call-next-method instance)
                     (slot-ref instance 'value))))

    (let ((enumerates (map (lambda (name value)
                             (let* ((StudlyName (string-append (clr/StudlyName enum-class)
                                                               "." name))
                                    (instance (make enum-class
                                                    :StudlyName StudlyName
                                                    :value value))
                                    (thunk (lambda () instance)))
                               (dotnet-message 4 "Enum" name "=" value)
                               (hash-table-put! *clr-static-field-getters*
                                                (StudlyName->key StudlyName)
                                                thunk)
                               (hash-table-put! *clr-public-static-field-getters*
                                                (StudlyName->key StudlyName)
                                                thunk)
                               instance))
                           names vals)))

      (add-method enum/enumerates
        (make (*default-method-class*)
          :arity 1
          :specializers (list (singleton enum-class))
          :procedure (lambda (call-next-method class)
                       enumerates)))

      (slot-set! enum-class 'argument-marshaler (if flag?
                                                    (flags-enumerate->foreign enum-class)
                                                    (enumerate->foreign enum-class)))

      (slot-set! enum-class 'return-marshaler (if flag?
                                                  (foreign->flags-enumerate enum-class)
                                                  (foreign->enumerate enum-class)))

      (add-method wrap-clr-object
        (make (*default-method-class*)
          :arity 2
          :specializers (list (singleton enum-class))
          :procedure (let ((marshaler (return-marshaler enum-class)))
                       (lambda (call-next-method class object)
                         (marshaler
                          (clr-convert/%change-type object clr-type-handle/system-int32))))))
      )))

(define (bootstrap-clr-classes! bootstrap-clr-object)
  (setup-type-type bootstrap-clr-object)
  (setup-system-object)
  (setup-reflection)

                                        ;(setup-system-enum)
  )

;;; End of bootstrap code for .NET class hierarchy.

;; Given a CLR class, iterate over all `members'
;; This is used by the method discovery code below.
(define (clr-class/for-selected-members function clr-class member-types static? public?)
  (let* ((members (clr-type/%get-members (clr-object/clr-handle clr-class) static? public?))
         (limit   (clr-array/length members)))
    (let loop ((idx 0))
      (if (< idx limit)
          (let* ((item (clr/%foreign-aref members idx))
                 (item-member-type (clr-memberinfo/member-type item)))
            (if (member item-member-type member-types)
                (function (clr-object->clr-instance item) item-member-type))
            (loop (+ idx 1)))))))

;(define (clr/class-members clr-class)
;  (let ((collection '()))
;    (clr-class/for-each-type-member
;     (if allow-private?
;         (lambda (private-member)
;           (set! collection (cons member collection)))
;         (lambda (private-member)
;           #f))
;     (lambda (public-member)
;       (set! collection (cons public-member collection)))
;     clr-class)
;    collection))

(define (list-clr-classes)
  (map-dotnet-classes identity))

;; Given a symbol, find the CLR class associated with it,
;; fetching and instantiating it on the fly from the CLR
;; type object if necessary.
(define (clr/find-class StudlyName)
  (hash-table-get
   *clr-type-table* (cond ((string? StudlyName) (StudlyName->key StudlyName))
                          ((symbol? StudlyName) StudlyName)
                          (else (error "Cannot find class " StudlyName)))
   (lambda ()
     ;; (dotnet-message "clr/find-class failure")
     ;; Go fetch it from .NET
     ;; Problem here is that the underlying code is being case sensitive.
     (clr-object->class (find-clr-type StudlyName)))))

(define (clr-object/potential-types clr-object)
  (let ((raw-object (clr-object/clr-handle clr-object))
        (potential-types '()))
    (map-dotnet-classes (lambda (class)
                          (if (clr/%isa? raw-object (clr-object/clr-handle class))
                              (set! potential-types (cons class potential-types)))))
    potential-types))

(define (clr-dynamic-cast new-class clr-object)
  (let ((raw-object (clr-object/clr-handle clr-object))
        (raw-type   (clr-object/clr-handle new-class)))
    (if (clr/%isa? raw-object raw-type)
        (wrap-clr-object new-class raw-object)
        (error "Cannot cast object to new type " clr-object new-class))))

(define (clr-object->clr-instance clr-object)
  (if (clr/%null? clr-object)
      '()
      (wrap-clr-object
       (hash-table-get *clr-type-table* (StudlyName->key (clr/%type-as-string clr-object))
                       (lambda () (clr-object->class (clr/%object-type clr-object))))
       clr-object)))

(define (flags-enumerate->foreign class)
  (lambda (flag-list)
    (clr-enum/to-object
     (clr-object/clr-handle class)
     (foldl (lambda (accum enumerate)
              (logior accum (enum/value enumerate)))
            0 flag-list))))

(define (enumerate->foreign class)
  (lambda (enumerate)
    (clr-enum/to-object (clr-object/clr-handle class) (enum/value enumerate))))

(define (biglogand left right)
  (if (and (odd? left) (odd? right))
      (cond ((= left -1) right)
            ((= right -1) left)
            (else (+ (* (biglogand (quotient left 2) (quotient right 2)) 2) 1)))
      (cond ((= left 0) 0)
            ((= right 0) 0)
            (else (* (biglogand (quotient left 2) (quotient right 2)) 2)))))

(define (biglogxor left right)
  (cond ((= left right) 0)
        ((or (and (even? left) (even? right))
             (and (odd? left) (odd? right)))
         (* (biglogxor (quotient left 2) (quotient right 2)) 2))
        (else (+ (* (biglogxor (quotient left 2) (quotient right 2)) 2) 1))))

(define (foreign->flags-enumerate class)
  (define (is-flag? enum)
    (let loop ((probe 1)
               (val (enum/value enum)))
      (cond ((= probe val) #t)
            ((> probe val) #f)
            (else (loop (* probe 2) val)))))

  (let ((enumerates (filter is-flag? (enum/enumerates class))))
    (lambda (foreign)
      (let loop ((value (clr/foreign->int foreign))
                 (scan  enumerates)
                 (result '()))
        (cond ((zero? value) (reverse! result))
              ((pair? scan) (let ((thisone (car scan)))
                              (if (zero? (biglogand value (enum/value thisone)))
                                  (loop value (cdr scan) result)
                                  (loop (biglogxor value (enum/value thisone))
                                        (cdr scan)
                                        (cons thisone result)))))
              (else (let ((value (clr/foreign->int foreign)))
                      (or (find-if (lambda (e) (= (enum/value e) value)) enumerates)
                          value))))))))

(define (foreign->enumerate class)
  (let ((enumerates (enum/enumerates class)))
    (lambda (foreign)
      (let ((value (clr/foreign->int foreign)))
        (or (find-if (lambda (e) (= (enum/value e) value)) enumerates)
            ;;(error "No enum for value" class value)
            value)))))

(define (parse-clr-parameters raw-parameters)
  (let loop ((i 0)
             (limit (clr-array/length raw-parameters))
             (required-parameter-count 0)
             (optional-parameter-count 0)
             (default-values '())
             (specializers '())
             (parameter-marshalers '()))
    (if (>= i limit)
        (values required-parameter-count
                optional-parameter-count
                default-values
                (reverse! specializers)
                (reverse! parameter-marshalers))
        (let* ((raw-parameter  (clr/%foreign-aref raw-parameters i))
               (parameter-type (clr-object->class (clr-parameterinfo/%parameter-type raw-parameter))))
          (if (clr-parameterinfo/is-optional? raw-parameter)
              (loop (+ i 1)
                    limit
                    required-parameter-count
                    (+ optional-parameter-count 1)
                    (cons (wrap-clr-object parameter-type (clr-parameterinfo/%default-value raw-parameter))
                          default-values)
                    specializers
                    (cons (argument-marshaler parameter-type) parameter-marshalers))
              (loop (+ i 1)
                    limit
                    (+ required-parameter-count 1)
                    optional-parameter-count
                    default-values
                    (cons (argument-specializer parameter-type) specializers)
                    (cons (argument-marshaler parameter-type) parameter-marshalers)))))))

(define (clr-fieldinfo/field-type info)
  (clr-object->class (clr-fieldinfo/%field-type info)))

(define (clr-memberinfo/declaring-type info)
  (clr-object->class (clr-memberinfo/%declaring-type info)))

(define (clr-methodbase/get-parameters info)
  (parse-clr-parameters (clr-methodbase/%get-parameters info)))

(define (clr-methodinfo/return-type info)
  (clr-object->class (clr-methodinfo/%return-type info)))

(define (clr-propertyinfo/get-index-parameters info)
  (parse-clr-parameters (clr-propertyinfo/%get-index-parameters info)))

(define (clr-propertyinfo/property-type info)
  (clr-object->class (clr-propertyinfo/%property-type info)))

(define (marshal-out max-arity marshalers arguments default-values)
  (let ((result (make-vector max-arity)))
    (define (loop1 index marshalers arguments)
      (cond ((pair? arguments)
             (vector-set! result index  ((car marshalers) (car arguments)))
             (loop1 (+ index 1) (cdr marshalers) (cdr arguments)))
            ((null? arguments) (loop2 max-arity index (reverse marshalers) default-values))
            (else (error "bad list of arguments"))))

    (define (loop2 index limit marshalers defaults)
      (let ((new-index (- index 1)))
        (if (< new-index limit)
            result
            (begin (vector-set! result new-index ((car marshalers) (car defaults)))
                   (loop2 new-index limit (cdr marshalers) (cdr defaults))))))

    (loop1 0 marshalers arguments)))

(define (clr-constructor-info->method class info)
  (call-with-values
   (lambda () (clr-methodbase/get-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let ((name (clr-memberinfo/name info))
           (arity (if (= optional-parameter-count 0)
                      required-parameter-count
                      (make-arity-at-least required-parameter-count)))
           (max-arity (+ optional-parameter-count required-parameter-count 1))
           (in-marshaler (return-marshaler (clr-memberinfo/declaring-type info))))
       (make class
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers specializers
         :procedure (nary->fixed-arity
                     (lambda (call-next-method . args)
                       (dotnet-message 4 "Invoking constructor" name)
                       (in-marshaler
                        (clr/%invoke-constructor info
                                                 (marshal-out (+ optional-parameter-count
                                                                 required-parameter-count)
                                                              out-marshalers args default-values))))
                     (arity-plus arity 1)))))))

(define (clr-method-info->static-method class info)
  (call-with-values
   (lambda () (clr-methodbase/get-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let ((name (clr-memberinfo/name info))
           (arity (if (= optional-parameter-count 0)
                      required-parameter-count
                      (make-arity-at-least required-parameter-count)))
           (max-arity (+ optional-parameter-count required-parameter-count 1))
           (in-marshaler (return-marshaler (clr-methodinfo/return-type info))))
       (make class
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers specializers
         :procedure (nary->fixed-arity
                     (lambda (call-next-method . args)
                       (dotnet-message 4 "Invoking static method" name)
                       (in-marshaler
                        (clr/%invoke info
                                     #f
                                     (marshal-out (+ optional-parameter-count required-parameter-count)
                                                  out-marshalers args default-values))))
                     (arity-plus arity 1)))))))

(define (clr-method-info->method class info)
  (call-with-values
   (lambda () (clr-methodbase/get-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let* ((declaring-type (clr-memberinfo/declaring-type info))
            (name (clr-memberinfo/name info))
            (instance-marshaler (argument-marshaler declaring-type))
            (arity (if (= optional-parameter-count 0)
                       (+ required-parameter-count 1)
                       (make-arity-at-least (+ required-parameter-count 1))))
            (max-arity (+ optional-parameter-count required-parameter-count 2))
            (in-marshaler (return-marshaler (clr-methodinfo/return-type info))))
       (make class
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers (cons (argument-specializer declaring-type) specializers)
         :procedure (nary->fixed-arity
                     (lambda (call-next-method instance . args)
                       (dotnet-message 4 "Invoking method" name)
                       (in-marshaler
                        (clr/%invoke info
                                     (instance-marshaler instance)
                                     (marshal-out (+ optional-parameter-count required-parameter-count)
                                                  out-marshalers args default-values))))
                     (arity-plus arity 1)))))))

(define (clr-object->method class object)
  (let ((member-type (clr-memberinfo/member-type object)))
    (cond ((= member-type clr-member-type/constructor)
           (clr-constructor-info->method class object))
          ((= member-type clr-member-type/method)
           (if (clr-methodbase/is-static? object)
               (clr-method-info->static-method class object)
               (clr-method-info->method class object)))
          (else (error "Can't make a method from this " object)))))

;;;; Generic functions on CLR objects.
;;;
;;; Methods on CLR objects will map into methods on generic functions.
;;; These will be created dynamically.  Since dynamic importing of top-level
;;; names could be a problem, we'll translate top-level identifiers that
;;; have leading dots to something that looks up the appropriately named
;;; generic function in the *CLR-GENERICS* hash table.

;;; What we want to do is add an AFTER method to INITIALIZE-INSTANCE on
;;; System.RuntimeType so that whenever we create a new type we probe
;;; for the properties, fields, etc. and augment or construct the
;;; appropriate methods.  However, this would cause an infinite loop
;;; because the member descriptors refer to type objects that have not
;;; yet been loaded.  To solve this, we do the following:

;;;  1.  Iterate over all existing types probing for their members.
;;;      This will instantiate new types who's methods are unknown.
;;;
;;;  2.  Iterate over all new types just instantiated to get *their*
;;;      members.  This may instantiate even more types.
;;;
;;;  3.  Repeat step 2 until no new types are created.  At this point,
;;;      it should be possible to instantiate new methods without the
;;;      possibility of inifite loops.
;;;
;;;  4.  Install the AFTER method so that methods are instantiated right
;;;      after instantiating the type.

(define <clr-method>
  (let ((<clr-method>
         (rec-allocate-instance
          (*default-entityclass-class*)
          (list
           :direct-default-initargs #f
           :direct-supers (list <method>)
           :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle)
                               (list 'max-arity :initarg :max-arity :reader 'max-arity))
           :name '<clr-method>))))
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list
          :direct-default-initargs #f
          :direct-supers (list <method>)
          :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle)
                              (list 'max-arity :initarg :max-arity :reader 'max-arity))
          :name '<clr-method>)))
    (rec-initialize
     <clr-method>
     (list
      :direct-default-initargs #f
      :direct-supers (list <method>)
      :direct-slots (list (list 'clr-handle :initarg :clr-handle :reader 'clr-object/clr-handle)
                          (list 'max-arity :initarg :max-arity :reader 'max-arity))
      :name '<clr-method>))
    <clr-method>))

(add-method max-arity
  (make (*default-method-class*)
    :arity 1
    :specializers (list <clr-method>)
    :procedure (lambda (call-next-method x)
                 (slot-ref x 'max-arity))))

(add-method clr-object/clr-handle
  (make (*default-method-class*)
    :arity 1
    :specializers (list <clr-method>)
    :procedure (lambda (call-next-method instance)
                 (slot-ref instance 'clr-handle))))

(define <clr-instance-field-getter>
  (let ((<clr-instance-field-getter>
         (rec-allocate-instance
          (*default-entityclass-class*)
          (list :direct-default-initargs #f
                :direct-supers (list <clr-method>)
                :direct-slots '()
                :name '<clr-instance-field-getter>))))
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list :direct-default-initargs #f
               :direct-supers (list <clr-method>)
               :direct-slots '()
               :name '<clr-instance-field-getter>)))
    (rec-initialize
     <clr-instance-field-getter>
     (list :direct-default-initargs #f
           :direct-supers (list <clr-method>)
           :direct-slots '()
           :name '<clr-instance-field-getter>))
    <clr-instance-field-getter>))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-instance-field-getter>)
    :arity 3
    :procedure ((lambda ()
                  (define (print-object call-next-method object port slashify)
                    (let* ((clr-object  (clr-object/clr-handle object))
                           (decl-type   (clr/%to-string
                                         (clr-object/clr-handle (clr-memberinfo/declaring-type clr-object))))
                           (printed-rep (clr/%to-string clr-object)))

                      (display "#<CLR-FIELD-GETTER " port)
                      (display decl-type port)
                      (display " " port)
                      (display printed-rep port)
                      (display ">" port)))
                  print-object))))

(define (clr-field-info->getter-procedure field-info)
  (let* ((name (clr-memberinfo/name field-info))
         (declaring-type (clr-memberinfo/declaring-type field-info))
         (instance-marshaler (argument-marshaler declaring-type))
         (in-marshaler (return-marshaler (clr-fieldinfo/field-type field-info))))
    (lambda (instance)
      (dotnet-message 4 "Getting field" name)
      (in-marshaler
       (clr/%field-ref field-info (instance-marshaler instance) '#())))))

(define (clr-field-info->getter-method info)
  (make <clr-instance-field-getter>
    :arity 1
    :max-arity 2
    :clr-handle info
    :name (clr-memberinfo/name info)
    :specializers (list (argument-specializer (clr-memberinfo/declaring-type info)))
    :procedure (let ((getter (clr-field-info->getter-procedure info)))
                 (lambda (call-next-method instance)
                   (getter instance)))))

(define (clr-property-info->getter-method info)
  (call-with-values
   (lambda () (clr-propertyinfo/get-index-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let* ((name (clr-memberinfo/name info))
            (declaring-type (clr-memberinfo/declaring-type info))
            (instance-marshaler (argument-marshaler declaring-type))
            (arity (if (= optional-parameter-count 0)
                       (+ required-parameter-count 1)
                       (make-arity-at-least (+ required-parameter-count 1))))
            (max-arity (+ optional-parameter-count required-parameter-count 2))
            (in-marshaler (return-marshaler (clr-propertyinfo/property-type info))))
       ;; (dotnet-message "in-marshaler" in-marshaler (clr-propertyinfo/property-type info))
       ;; (dotnet-message "instance-marshaler" instance-marshaler declaring-type)
       ;; (dotnet-message "out-marshalers" out-marshalers)
       (make <clr-instance-field-getter>
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers (cons (argument-specializer declaring-type) specializers)
         :procedure (nary->fixed-arity
                     (lambda (call-next-method instance . args)
                       (dotnet-message 4 "Getting property" name)
                       (in-marshaler
                        (clr/%property-ref info
                                           (instance-marshaler instance)
                                           (marshal-out (+ optional-parameter-count
                                                           required-parameter-count)
                                                        out-marshalers args default-values))))
                     (arity-plus arity 1)))))))

(define <clr-static-field-getter>
  (let ((<clr-static-field-getter>
         (rec-allocate-instance
          (*default-entityclass-class*)
          (list :direct-default-initargs #f
                :direct-supers (list <clr-method>)
                :direct-slots '()
                :name '<clr-static-field-getter>))))
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list :direct-default-initargs #f
               :direct-supers (list <clr-method>)
               :direct-slots '()
               :name '<clr-static-field-getter>)))
    (rec-initialize
     <clr-static-field-getter>
     (list :direct-default-initargs #f
           :direct-supers (list <clr-method>)
           :direct-slots '()
           :name '<clr-static-field-getter>))
    <clr-static-field-getter>))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-static-field-getter>)
    :arity 3
    :procedure ((lambda ()
                  (define (print-object call-next-method object port slashify)
                    (let* ((clr-object  (clr-object/clr-handle object))
                           (decl-type   (clr/%to-string
                                         (clr-object/clr-handle (clr-memberinfo/declaring-type clr-object))))
                           (printed-rep (clr-memberinfo/name clr-object)))

                      (display "#<CLR-FIELD-GETTER " port)
                      (display decl-type port)
                      (display "." port)
                      (display printed-rep port)
                      (display ">" port)))
                  print-object))))

(define (clr-field-info->static-getter-method info)
  (let ((name (clr-memberinfo/name info))
        (in-marshaler (return-marshaler (clr-fieldinfo/field-type info))))
    (make <clr-static-field-getter>
      :arity 0
      :max-arity 1
      :clr-handle info
      :name name
      :specializers (list)
      :procedure (lambda (call-next-method)
                   (dotnet-message 4 "Getting static field" name)
                   (in-marshaler
                    (clr/%field-ref info clr/null '#()))))))

(define (clr-property-info->static-getter-method info)
  (call-with-values
   (lambda () (clr-propertyinfo/get-index-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let* ((name (clr-memberinfo/name info))
            (declaring-type (clr-memberinfo/declaring-type info))
            (arity (if (= optional-parameter-count 0)
                       required-parameter-count
                       (make-arity-at-least required-parameter-count)))
            (max-arity (+ optional-parameter-count required-parameter-count 1))
            (in-marshaler (return-marshaler (clr-propertyinfo/property-type info))))
       (make <clr-static-field-getter>
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers specializers
         :procedure (nary->fixed-arity
                     (lambda (call-next-method . args)
                       (dotnet-message 4 "Getting static property" name)
                       (in-marshaler
                        (clr/%property-ref info
                                           clr/null
                                           (marshal-out (+ optional-parameter-count required-parameter-count)
                                                        out-marshalers args default-values))))
                     (arity-plus arity 1)))))))

(define <clr-static-field-setter>
  (let ((<clr-static-field-setter>
         (rec-allocate-instance
          (*default-entityclass-class*)
          (list :direct-default-initargs #f
                :direct-supers (list <clr-method>)
                :direct-slots '()
                :name '<clr-static-field-setter>))))
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list :direct-default-initargs #f
               :direct-supers (list <clr-method>)
               :direct-slots '()
               :name '<clr-static-field-setter>)))
    (rec-initialize
     <clr-static-field-setter>
     (list :direct-default-initargs #f
           :direct-supers (list <clr-method>)
           :direct-slots '()
           :name '<clr-static-field-setter>))
    <clr-static-field-setter>))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-static-field-setter>)
    :arity 3
    :procedure ((lambda ()
                  (define (print-object call-next-method object port slashify)
                    (let* ((clr-object  (clr-object/clr-handle object))
                           (decl-type   (clr/%to-string
                                         (clr-object/clr-handle (clr-memberinfo/declaring-type clr-object))))
                           (printed-rep (clr-memberinfo/name clr-object)))

                      (display "#<CLR-FIELD-SETTER " port)
                      (display decl-type port)
                      (display "." port)
                      (display printed-rep port)
                      (display ">" port)))
                  print-object))))

(define (clr-field-info->static-setter-method info)
  (let ((name (clr-memberinfo/name info))
        (new-value-marshaler (argument-marshaler (clr-fieldinfo/field-type info))))
    (make <clr-static-field-setter>
      :arity 1
      :max-arity 2
      :clr-handle info
      :name name
      :specializers (list (argument-specializer (clr-fieldinfo/field-type info)))
      :procedure (lambda (call-next-method new-value)
                   (dotnet-message 4 "Setting static field" name)
                   (clr/%field-set! info clr/null (new-value-marshaler new-value))))))

(define (clr-property-info->static-setter-method info)
  (call-with-values
   (lambda () (clr-propertyinfo/get-index-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let* ((name (clr-memberinfo/name info))
            (declaring-type (clr-memberinfo/declaring-type info))
            (arity (if (= optional-parameter-count 0)
                       (+ required-parameter-count 1)
                       (make-arity-at-least (+ required-parameter-count 1))))
            (max-arity (+ optional-parameter-count required-parameter-count 2))
            (new-value-marshaler (argument-marshaler (clr-propertyinfo/property-type info))))
       (make <clr-static-field-setter>
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers (cons (argument-specializer (clr-propertyinfo/property-type info))
                             specializers)
         :procedure (nary->fixed-arity
                     (lambda (call-next-method new-value . args)
                       (dotnet-message 4 "Setting static property" name)
                       (clr/%property-set! info
                                           clr/null
                                           (new-value-marshaler new-value)
                                           (marshal-out (+ optional-parameter-count
                                                           required-parameter-count)
                                                        out-marshalers args default-values))
                       (unspecified))
                     (arity-plus arity 1)))))))

(define <clr-instance-field-setter>
  (let ((<clr-instance-field-setter>
         (rec-allocate-instance
          (*default-entityclass-class*)
          (list :direct-default-initargs #f
                :direct-supers (list <clr-method>)
                :direct-slots '()
                :name '<clr-instance-field-setter>))))
    (if (*make-safely*)
        (check-initargs
         (*default-entityclass-class*)
         (list :direct-default-initargs #f
               :direct-supers (list <clr-method>)
               :direct-slots '()
               :name '<clr-instance-field-setter>)))
    (rec-initialize
     <clr-instance-field-setter>
     (list :direct-default-initargs #f
           :direct-supers (list <clr-method>)
           :direct-slots '()
           :name '<clr-instance-field-setter>))
    <clr-instance-field-setter>))

(add-method print-object
  (make (*default-method-class*)
    :specializers (list <clr-instance-field-setter>)
    :arity 3
    :procedure ((lambda ()
                  (define (print-object call-next-method object port slashify)
                    (let* ((clr-object  (clr-object/clr-handle object))
                           (decl-type   (clr/%to-string
                                         (clr-object/clr-handle (clr-memberinfo/declaring-type clr-object))))
                           (printed-rep (clr-memberinfo/name clr-object)))

                      (display "#<CLR-FIELD-SETTER " port)
                      (display decl-type port)
                      (display "." port)
                      (display printed-rep port)
                      (display ">" port)))
                  print-object))))

(define (clr-field-info->setter-method info)
  (let* ((name (clr-memberinfo/name info))
         (declaring-type (clr-memberinfo/declaring-type info))
         (instance-marshaler (argument-marshaler declaring-type))
         (new-value-marshaler (argument-marshaler (clr-fieldinfo/field-type info))))
    (make  <clr-instance-field-setter>
      :arity 2
      :max-arity 3
      :clr-handle info
      :name name
      :specializers (list (argument-specializer declaring-type)
                          (argument-specializer (clr-fieldinfo/field-type info)))
      :procedure (lambda (call-next-method instance new-value)
                   (dotnet-message 4 "Setting field" name)
                   (clr/%field-set! info
                                    (instance-marshaler instance)
                                    (new-value-marshaler new-value))
                   (unspecified)))))

(define (clr-property-info->setter-method info)
  (call-with-values
   (lambda () (clr-propertyinfo/get-index-parameters info))
   (lambda (required-parameter-count
            optional-parameter-count
            default-values
            specializers
            out-marshalers)
     (let* ((name (clr-memberinfo/name info))
            (declaring-type (clr-memberinfo/declaring-type info))
            (instance-marshaler (argument-marshaler declaring-type))
            (arity (if (= optional-parameter-count 0)
                       (+ required-parameter-count 2)
                       (make-arity-at-least (+ required-parameter-count 2))))
            (max-arity (+ optional-parameter-count required-parameter-count 3))
            (new-value-marshaler (argument-marshaler (clr-propertyinfo/property-type info))))
       (make <clr-instance-field-setter>
         :arity arity
         :max-arity max-arity
         :clr-handle info
         :name name
         :specializers (list* (argument-specializer declaring-type)
                              (argument-specializer (clr-propertyinfo/property-type info))
                              specializers)
         :procedure (nary->fixed-arity
                     (lambda (call-next-method instance new-value . args)
                       (dotnet-message 4 "Setting property" name)
                       (clr/%property-set! info
                                           (instance-marshaler instance)
                                           (new-value-marshaler new-value)
                                           (marshal-out (+ optional-parameter-count
                                                           required-parameter-count)
                                                        out-marshalers args default-values))
                       (unspecified))
                     (arity-plus arity 1)))))))

(define (find-or-create-generic table name arity min-arity)
  (define (create-generic)
    (make <clr-generic>
      :arity arity
      :name (StudlyName->key name)
      :StudlyName name))

  (let* ((key-name (StudlyName->key name))
         (generic  (hash-table-get
                    table key-name
                    (lambda ()
                      (let ((generic (create-generic)))
                        (hash-table-put! table key-name generic)
                        generic)))))

    (cond ((instance-of? generic <clr-arity-overload>)
           (ensure-overload-vector-capacity generic arity)
           (let ((arity-vector (get-arity-vector generic)))
             (or (vector-ref arity-vector arity)
                 (let ((generic (create-generic)))
                   (vector-set! arity-vector arity generic)
                   generic))))
          ((= (generic-arity generic) arity) generic)
          (else
           ;; When we reach here, we have a `normal' generic function
           ;; that we got from the table and we want to make an
           ;; `overload' But someone may have cached the original
           ;; generic, so we can't just replace it in the table, we
           ;; have to mutate the instance object itself.  The
           ;; `change-class' protocol would come in handy, but rather
           ;; than implement that for this one use, we do the truly
           ;; nasty trick of bashing the instance representation
           ;; directly!

           ;; Do not try this trick at home.
           (let* ((arity-vector (make-vector (+ (max arity (generic-arity generic)) 1)
                                             #f))

                  (overload (make <clr-arity-overload>
                              :arity (make-arity-at-least min-arity)
                              :arity-vector arity-vector
                              :name key-name
                              :StudlyName name))

                  ;; Make an uninitialized instance to hold the guts of
                  ;; the table entry.
                  (duplicate-of-original (%make-instance #f #f))

                  ;; And a new generic which will be the result of this
                  ;; call.
                  (new-generic (create-generic)))

             ;; Put our new generic into the arity vector
             (vector-set! arity-vector arity new-generic)

             ;; Put the uninitialized duplicate into the arity vector
             (vector-set! arity-vector (generic-arity generic) duplicate-of-original)

             ;; Now the gross part.  Bash out the representation of
             ;; the duplicate with the representation of the original
             ;; generic.  The duplicate will be identical to the
             ;; original, but NOT EQ? to it.
             (instance/replace! duplicate-of-original generic)
             (%set-instance/procedure! duplicate-of-original
                                       (compute-apply-generic duplicate-of-original))

             ;; And bash out the representation of the original
             ;; generic with the representation of the overload.  Now
             ;; anyone that had cached the original will now be
             ;; caching the overload.
             (instance/replace! generic overload)
             (%set-instance/procedure! generic
                                       (compute-apply-generic generic))

             ;; finally return the new generic
             new-generic)))))

(define (install-method method tables name extra-args)
  (dotnet-message 3 "Installing" method)
  (let ((min-arity (let ((arity (method-arity method)))
                     (if (arity-at-least? arity)
                         (arity-at-least-value arity)
                         arity)))
        (limit (max-arity method)))
    (do ((argcount min-arity (+ argcount 1)))
        ((>= argcount limit) (unspecified))
      (for-each (lambda (table)
                  (add-method (find-or-create-generic table name argcount extra-args)
                    method))
                tables))))

(define *clr-generics* (make-hash-table 'symbol-eq?))
(define *clr-public-generics* (make-hash-table 'symbol-eq?))

(define (clr/find-generic allow-private? name)
  (hash-table-get
   (if allow-private? *clr-generics* *clr-public-generics*)  name
   (lambda ()
     ;; If the generic isn't here, perhaps it will be demand loaded
     ;; by the time we evaluate all the arguments.
     (lambda arguments
       (apply (hash-table-get
               (if allow-private? *clr-generics* *clr-public-generics*) name
               (lambda ()
                 (error "CLR-GENERIC (or overload) not found: " name)))
              arguments)))))

(define (install-instance-method name method public?)
  (install-method method
                  (if public?
                      (list *clr-generics* *clr-public-generics*)
                      (list *clr-generics*))
                  name
                  1))

(define *clr-static-methods* (make-hash-table 'symbol-eq?))
(define *clr-public-static-methods* (make-hash-table 'symbol-eq?))

(define (clr/find-static-method allow-private? name)
  (hash-table-get
   (if allow-private? *clr-static-methods* *clr-public-static-methods*) name
   (lambda ()
     ;; If the static method isn't here, perhaps the class needs to be
     ;; loaded.
     (let loop ((as-string (symbol->string name))
                (scan (string-length (symbol->string name))))
       (cond ((= scan 0) (error "Bogus name to clr/find-static-method"))
             ((char=? (string-ref as-string (- scan 1)) #\.)
              (let ((class-name (substring as-string 0 (- scan 1))))
                (if (clr/find-class class-name)
                    (hash-table-get
                     (if allow-private? *clr-static-methods* *clr-public-static-methods*) name
                     (lambda ()
                       (error "CLR-STATIC-METHOD not found: " name)))
                    (error "CLR-STATIC-METHOD not found (class not found): " name))))
             (else (loop as-string (- scan 1))))))))

(define (install-static-method name method public?)
  (install-method method
                  (if public?
                      (list *clr-static-methods*
                            *clr-public-static-methods*)
                      (list *clr-static-methods*))
                  name
                  0))

(define *clr-constructors* (make-hash-table 'symbol-eq?))
(define *clr-public-constructors* (make-hash-table 'symbol-eq?))

(define (clr/find-constructor allow-private? name)
  (hash-table-get
   (if allow-private? *clr-constructors* *clr-public-constructors*) name
   (lambda ()
     (let ((class-name (symbol->string name)))
       (if (clr/find-class class-name)
           (hash-table-get
            (if allow-private? *clr-constructors* *clr-public-constructors*) name
            (lambda ()
              (error "CLR-CONSTRUCTOR not found: " name)))
           (error "CLR-CONSTRUCTOR not found (class not found): " name))))))

(define (install-constructor constructor public?)
  (install-method constructor
                  (if public?
                      (list *clr-constructors*
                            *clr-public-constructors*)
                      (list *clr-constructors*))
                  (clr/StudlyName
                   (clr-memberinfo/declaring-type
                    (clr-object/clr-handle constructor)))
                  0))

(define *clr-static-field-getters* (make-hash-table 'symbol-eq?))
(define *clr-public-static-field-getters* (make-hash-table 'symbol-eq?))

(define (clr/find-static-field-getter allow-private? name)
  (hash-table-get
   (if allow-private? *clr-static-field-getters* *clr-public-static-field-getters*) name
   (lambda ()
     ;; If the static field isn't here, perhaps the class needs to be
     ;; loaded.
     (let loop ((as-string (symbol->string name))
                (scan (string-length (symbol->string name))))
       (cond ((= scan 0) (error "Bogus name to clr/find-static-field-getter"))
             ((char=? (string-ref as-string (- scan 1)) #\.)
              (let ((class-name (substring as-string 0 (- scan 1))))
                (if (clr/find-class class-name)
                    (hash-table-get
                     (if allow-private? *clr-static-field-getters* *clr-public-static-field-getters*) name
                     (lambda ()
                       (error "CLR-STATIC-FIELD not found: " name)))
                    (error "CLR-STATIC-FIELD not found (class not found): " name))))
             (else (loop as-string (- scan 1))))))))

(define (install-static-field-reader name reader public?)
  (install-method reader
                  (if public?
                      (list *clr-static-field-getters*
                            *clr-public-static-field-getters*)
                      (list *clr-static-field-getters*))
                  name
                  0))

(define *clr-static-field-setters* (make-hash-table 'symbol-eq?))
(define *clr-public-static-field-setters* (make-hash-table 'symbol-eq?))

(define (clr/find-static-field-setter allow-private? name)
  (hash-table-get
   (if allow-private? *clr-static-field-setters* *clr-public-static-field-setters*) name
   (lambda ()
     ;; If the static field isn't here, perhaps the class needs to be
     ;; loaded.
     (let loop ((as-string (symbol->string name))
                (scan (string-length (symbol->string name))))
       (cond ((= scan 0) (error "Bogus name to clr/find-static-field-setter"))
             ((char=? (string-ref as-string (- scan 1)) #\.)
              (let ((class-name (substring as-string 0 (- scan 1))))
                (if (clr/find-class class-name)
                    (hash-table-get
                     (if allow-private? *clr-static-field-setters* *clr-public-static-field-setters*) name
                     (lambda ()
                       (error "CLR-STATIC-FIELD not found: " name)))
                    (error "CLR-STATIC-FIELD not found (class not found): " name))))
             (else (loop as-string (- scan 1))))))))

(define (install-static-field-writer name writer public?)
  (install-method writer
                  (if public?
                      (list *clr-static-field-setters*
                            *clr-public-static-field-setters*)
                      (list *clr-static-field-setters*))
                  name
                  0))

(define *clr-instance-field-getters* (make-hash-table 'symbol-eq?))
(define *clr-public-instance-field-getters* (make-hash-table 'symbol-eq?))

(define (clr/find-instance-field-getter allow-private? name)
  (hash-table-get
   (if allow-private? *clr-instance-field-getters* *clr-public-instance-field-getters*) name
   (lambda ()
     (lambda arguments
       ;; If it isn't here, perhaps it will be demand loaded
       ;; by the time we evaluate all the arguments.
       (apply (hash-table-get
               (if allow-private? *clr-instance-field-getters* *clr-public-instance-field-getters*)
               name
               (lambda ()
                 (error "CLR-INSTANCE-FIELD-GETTER not found: " name)))
              arguments)))))

(define (install-instance-field-reader name reader public?)
  (install-method reader
                  (if public?
                      (list *clr-instance-field-getters*
                            *clr-public-instance-field-getters*)
                      (list *clr-instance-field-getters*))
                  name
                  1))

(define *clr-instance-field-setters* (make-hash-table 'symbol-eq?))
(define *clr-public-instance-field-setters* (make-hash-table 'symbol-eq?))

(define (clr/find-instance-field-setter allow-private? name)
  (hash-table-get
   (if allow-private? *clr-instance-field-setters* *clr-public-instance-field-setters*) name
   (lambda ()
     (lambda arguments
       ;; If it isn't here, perhaps it will be demand loaded
       ;; by the time we evaluate all the arguments.
       (apply (hash-table-get
               (if allow-private? *clr-instance-field-setters* *clr-public-instance-field-setters*)
               name
               (lambda ()
                 (error "CLR-INSTANCE-FIELD-SETTER not found: " name)))
              arguments)))))

(define (install-instance-field-writer name writer public?)
  (install-method writer
                  (if public?
                      (list *clr-instance-field-setters*
                            *clr-public-instance-field-setters*)
                      (list *clr-instance-field-setters*))
                  name
                  2))

(define (make-static-name handle)
  (string-append
   (clr/StudlyName
    (clr-memberinfo/declaring-type handle))
   "."
   (clr-memberinfo/name handle)))


(define (process-event clr-event-info public?)
  (dotnet-message 2 "Processing event" clr-event-info)
  ;; (process-method-or-constructor clr-event-info public?)
  #f
  )

(define (process-static-literal handle public?)
  (let* ((marshaler (return-marshaler (clr-fieldinfo/field-type handle)))
         (literal-value (marshaler (clr-field-info/%get-value handle)))
         (key (StudlyName->key (make-static-name handle)))
         (thunk (lambda () literal-value)))
      (hash-table-put! *clr-static-field-getters* key thunk)
      (if public?
          (hash-table-put! *clr-public-static-field-getters* key thunk))))

(define (process-field handle public?)
  (let ((name (clr-memberinfo/name handle)))
    (install-instance-field-reader name (clr-field-info->getter-method handle) public?)
    (if (not (clr-fieldinfo/is-init-only? handle))
        (install-instance-field-writer name (clr-field-info->setter-method handle) public?))))

(define (process-static-field handle public?)
  (install-static-field-reader (make-static-name handle)
                               (clr-field-info->static-getter-method handle) public?)
  (if (not (clr-fieldinfo/is-init-only? handle))
      (install-static-field-writer (make-static-name handle)
                                   (clr-field-info->static-setter-method handle)
                                   public?)))

(define (process-property handle public?)
  (let ((name (clr-memberinfo/name handle)))
    (install-instance-field-reader name (clr-property-info->getter-method handle) public?)
    (if (clr-propertyinfo/can-write? handle)
        (install-instance-field-writer name (clr-property-info->setter-method handle) public?))))

(define (process-static-property handle public?)
  (install-static-field-reader (make-static-name handle)
                               (clr-property-info->static-getter-method handle)
                               public?)
  (if (clr-propertyinfo/can-write? handle)
      (install-static-field-writer
       (make-static-name handle)
       (clr-property-info->static-setter-method handle)
       public?)))


(define (process-method-or-constructor clr-info public?)
  (let* ((handle      (clr-object/clr-handle clr-info))
         (member-type (clr-memberinfo/member-type handle)))
    (cond ((= member-type clr-member-type/constructor)
           (install-constructor clr-info public?))
          ((= member-type clr-member-type/method)
           (let ((name (clr-memberinfo/name handle)))
             (if (or (< (string-length name) 5)
                     (and (not (string=? (substring name 0 4) "get_"))
                          (not (string=? (substring name 0 4) "set_"))))
                 (if (clr-methodbase/is-static? handle)
                     (install-static-method (make-static-name handle) clr-info public?)
                     (install-instance-method name clr-info public?))
                 ;; Skip funky methods
                 #f)))
          (else (error "Process-method: bad method " clr-info)))))

(define (process-nested-type info public?)
  ;; Nested types should just work.
  ;; (dotnet-message "Ignoring nested type" info)
  #f
  )

;; The CLR info is an instance of System.Reflection.MemberInfo
;; that describes a property, constructor, enum, method, field, etc.
;; We examine what it is and augment (or create) the appropriate generic
;; function to handle it.
(define (process-member clr-info member-type public?)
  (let ((handle      (clr-object/clr-handle clr-info)))

    (cond ((= member-type clr-member-type/constructor)
           (dotnet-message 3 "Process constructor member" clr-info)
           ;; performed as initialization on constructor
           )

          ((= member-type clr-member-type/event)
           (dotnet-message 3 "Process event member" clr-info)
           (process-event clr-info public?))

          ((= member-type clr-member-type/field)
           (dotnet-message 3 "Process field member" clr-info)
           (if (clr-fieldinfo/is-static? handle)
               (if (clr-fieldinfo/is-literal? handle)
                   (process-static-literal handle public?)
                   (process-static-field handle public?))
               (process-field handle public?)))

          ((= member-type clr-member-type/method)
           (dotnet-message 3 "Process type member" clr-info)
           ;; performed as initialization on method
           )

          ((= member-type clr-member-type/property)
           (dotnet-message 3 "Process property member")
           (if (not public?)
               #f ;; there's a non-public property in the forms code that cause problems
               (if (clr-propertyinfo/can-read? handle)
                   (if (clr-methodbase/is-static? (clr-propertyinfo/%get-get-method handle (not public?)))
                       (process-static-property handle public?)
                       (process-property handle public?)))))

          ((= member-type clr-member-type/type-info)
           (error "process-member: type should not be a member of a type"))

          ((= member-type clr-member-type/custom)
           (dotnet-message 3 "Process custom member")
           (process-custom handle public?))

          ((= member-type clr-member-type/nested-type)
           (dotnet-message 3 "Process nested type")
           (process-nested-type clr-info public?))

          (else
           (error "process-member: unrecognized member type " member-type)))))

(define (process-enum class)
  ;; (dotnet-message "Skipping processing enum" class)
  #f
  )

(define (process-private-member info member-type)
  (process-member info member-type #f))

(define (process-public-member info member-type)
  (process-member info member-type #t))

;; Since creating generics is going to load a bunch of classes,
;; and we can't create them until a lot of them are in place,
;; we go through and process everything in the class table.
;; When we are done, we loop over the class table and process anything
;; new.  Iterate until we have everything.
;;
;; At the point where everything exists, we can add an after method
;; to create CLR methods on the fly when a new CLR class is
;; instantiated.
(define (initialize-clr-generics!)
  (let loop ((classes-processed '())
             (classes-to-process (list System.RuntimeType)))
    (display ".")
    (flush-output)
    (cond ((pair? classes-to-process)
           (for-each initialize-static-members! classes-to-process)
           (let* ((processed (set-union classes-to-process classes-processed))
                  (new (set-difference (list-clr-classes) processed)))
             (loop processed new)))
          ((null? classes-to-process) #f)
          (else (error "Bad list in initialize-clr-generics!"))))

  ;; Now add the after method to cause new class objects to initialize
  ;; the methods on the fly.
  (add-method initialize-instance
    (make (*default-method-class*)
      :arity 2
      :specializers (list System.RuntimeType)
      :procedure (lambda (call-next-method class initargs)
                   (initialize-static-members! class))
      :qualifier :after))

  (enable-auto-initialization!)

  (dotnet-message 1 "Bootstrapping complete. "
                  (length (list-clr-classes)) "classes,"
                  (hash-table-entries *clr-public-constructors*) "constructors,"
                  (- (hash-table-entries *clr-constructors*)
                     (hash-table-entries *clr-public-constructors*)) "private constructors,"
                  (hash-table-entries *clr-static-field-getters*) "static field getters,"
                  (- (hash-table-entries *clr-static-field-getters*)
                     (hash-table-entries *clr-public-static-field-getters*)) "private static field getters,"
                  (hash-table-entries *clr-static-field-setters*) "static field setters,"
                  (- (hash-table-entries *clr-static-field-setters*)
                     (hash-table-entries *clr-public-static-field-setters*)) "private static field setters,"
                  (hash-table-entries *clr-static-methods*) "static methods,"
                  (- (hash-table-entries *clr-static-methods*)
                     (hash-table-entries *clr-public-static-methods*)) "private static methods,"
                  (hash-table-entries *clr-generics*) "generics, and"
                  (- (hash-table-entries *clr-generics*)
                     (hash-table-entries *clr-public-generics*))
                  "private generics.")
  #t)

(define *dotnet-initialized* #f)

  ;; (provide initialize!)
(define (enable-dotnet!)
  (cond (*dotnet-initialized* #f)
        ((= (car (clr/%clr-version)) 1)
         (newline)
         (display "Initializing dotnet...")
         ;; (flush-output)
         ;; Enable profiling of the CLR so we can go in the back door.
         ;; DONE IN BATCH FILE
         ;; (putenv "Cor_Enable_Profiling" "1")
         ;; (putenv "Cor_Profiler" "MysterX.DotnetProfiler")

         (let ((root-clr-object clr-type-handle/system-type))
           ;; Bootstrap the classes needed to represent CLR objects.
           ;; After this, we can use the marshaling routines.
           (dotnet-message 0 "Bootstrap clr classes.")
           (bootstrap-clr-classes! root-clr-object)
           (dotnet-message 0 "Initialize clr generics.")
           (initialize-clr-generics!)
           (recognize-javadot-symbols? #t)
           (display "done.")))
        ((= (car (clr/%clr-version)) 2)
         (newline)
         (display "Initializing dotnet 2...")
         (let ((root-clr-object clr-type-handle/system-type))
           ;; Bootstrap the classes needed to represent CLR objects.
           ;; After this, we can use the marshaling routines.
           (dotnet-message 0 "Bootstrap clr classes.")
           (bootstrap-clr-classes! root-clr-object)
           (dotnet-message 0 "Initialize clr generics.")
           (initialize-clr-generics!)
           (recognize-javadot-symbols? #t)
           (display "done.")))

        (else (error (string-append
                      "Dotnet version "
                      (number->string (car (clr/%clr-version)))
                      (foldl (lambda (x y) (string-append x "." y)) "" (map number->string (cdr (clr/%clr-version))))
                      " not yet supported.")))))

;;;; Utilities
;;;
;;; Here's some trivial code that is used above.
(define (hash-table-entries hash-table)
  (length (hash-table-map hash-table (lambda (key value) #f))))

(define (set-union left right)
  (cond ((pair? left) (set-union (cdr left)
                                 (if (member (car left) right)
                                     right
                                     (cons (car left) right))))
        ((null? left) right)
        (else (error "set-union: improper list " left))))

(define (set-difference left right)
  (cond ((pair? left) (if (member (car left) right)
                          (set-difference (cdr left) right)
                          (cons (car left) (set-difference (cdr left) right))))
        ((null? left) '())
        (else (error "set-union: improper list " left))))


  ;; Given a procedure of at least ARITY args,
  ;; return a procedure of exacty ARITY args.
(define (nary->fixed-arity procedure arity)
  ;; Why thirty-wonderful flavors?
  ;; The generic function arity is determined by the
  ;; arity of the enclosed methods.  If we used
  ;; a rest arg here, then we'd be creating an n-ary
  ;; generic which we don't want.
  ;;
  ;; Yes, there is a procedure in .NET that takes
  ;; 31 arguments.  I think they left one out.
  (cond ((number? arity)
         (case arity
           ((0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
            (%nary->fixed-arity procedure arity))
           ((16) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15)))
           ((17) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16)))
           ((18) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17)))
           ((19) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18)))
           ((20) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19)))
           ((21) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20)))
           ((22) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21)))
           ((23) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22)))
           ((24) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23)))
           ((25) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24)))
           ((26) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25)))
           ((27) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26)))
           ((28) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27)))
           ((29) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28)))
           ((30) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29)))
           ((31) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                              arg30)))
           ((32) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30 arg31)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                              arg30 arg31)))
           ((33) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30 arg31 arg32)
                   (procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                              arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                              arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                              arg30 arg31 arg32)))

           (else (error "Need more of nary->fixed arity" arity))))
        ((arity-at-least? arity)
         (case (arity-at-least-value arity)
           ((0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15) (%nary->fixed-arity procedure arity))
           ((16) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 rest)))
           ((17) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 rest)))
           ((18) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 rest)))
           ((19) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 rest)))
           ((20) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19 rest)))
           ((21) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 rest)))
           ((22) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 rest)))
           ((23) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 rest)))
           ((24) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 rest)))
           ((25) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 rest)))
           ((26) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 rest)))
           ((27) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 rest)))
           ((28) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 rest)))
           ((29) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 rest)))
           ((30) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29 rest)))
           ((31) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                          arg30 rest)))
           ((32) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30 arg31 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                          arg30 arg31 rest)))
           ((33) (lambda (arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                               arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                               arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                               arg30 arg31 arg32 . rest)
                   (apply procedure arg0 arg1 arg2 arg3 arg4 arg5 arg6 arg7 arg8 arg9
                          arg10 arg11 arg12 arg13 arg14 arg15 arg16 arg17 arg18 arg19
                          arg20 arg21 arg22 arg23 arg24 arg25 arg26 arg27 arg28 arg29
                          arg30 arg31 arg32 rest)))

           (else (error "Need more of nary->fixed arity" arity))))
        (else (error "nary->fixed-arity:  not an arity" arity))))