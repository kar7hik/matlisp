(in-package #:matlisp)

(defmacro optimize-expression (decl &rest body)
  (with-memoization ()
    (memoizing
     (labels ((cl (vec)
		(if-let (alist (assoc vec decl))
		  (letv* (((ref place &key type &allow-other-keys) alist))
		    (if (subtypep type 'dense-tensor) type))))
	      (head-decl (vec)
		(when (cl vec)				 
		  (letv* (((ref place &key head &allow-other-keys) (assoc vec decl)))
		    (or head (with-gensyms (head) (values head `((,head (head ,vec) :type index-type))))))))
	      (store-decl (vec)
		(when (cl vec)				 
		  (letv* (((ref place &key store &allow-other-keys) (assoc vec decl)))
		    (or store (with-gensyms (store) (values store `((,store (store ,vec) :type ,(store-type (cl vec))))))))))
	      (strides-decl (vec)
		(when (cl vec)
		  (letv* (((ref place &key strides &allow-other-keys) (assoc vec decl)))
		    (or strides (with-gensyms (strides) (values strides `((,strides (strides ,vec) :type index-store-vector)))))))))
       (let ((opti
	      (maptree '(tb+ tb- tb*-opt tb/ matlisp-infix::generic-ref)
		       #'(lambda (x)
			   (match x
			     ((list* (and op (or 'tb+ 'tb- 'tb*-opt 'tb/)) rest)
			      (values (list* (cadr (assoc op '((tb+ cl:+) (tb- cl:-) (tb*-opt cl:*) (tb* cl:*) (tb/ cl:/)))) rest) #'mapcar))
			     ((and form (list* 'matlisp-infix::generic-ref vec subs))
			      (if (and (cl vec) (notany #'(lambda (x) (match x ((list* :slice _) t))) subs))
				  `(t/store-ref ,(cl vec) ,(store-decl vec)
						(the index-type
						     (cl:+ (the index-type ,(head-decl vec))
							   (the index-type
								(cl:+ ,@(mapcar (let ((nn -1))
										  #'(lambda (x) `(the index-type (cl:* (the index-type ,x)
														       (the index-type
															    ,(if (symbolp (strides-decl vec))
																 `(aref ,(strides-decl vec) ,(incf nn))
																 (elt (strides-decl vec) (incf nn))))))))
										subs))))))
				  form))))
		       body)))
	 `(let*-typed (,@(mapcan #'(lambda (x)
				     (letv* (((ref place &key type &allow-other-keys) x))
				       `((,ref ,place ,@(if type `(:type ,type)))
					 ,@(nth-value 1 (head-decl ref))
					 ,@(nth-value 1 (strides-decl ref))
					 ,@(nth-value 1 (store-decl ref)))))
				 decl))
	    ,@opti))))))
