;;; -*- Mode: lisp; Syntax: ansi-common-lisp; Package: :matlisp; Base: 10 -*-
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Copyright (c) 2000 The Regents of the University of California.
;;; All rights reserved. 
;;; 
;;; Permission is hereby granted, without written agreement and without
;;; license or royalty fees, to use, copy, modify, and distribute this
;;; software and its documentation for any purpose, provided that the
;;; above copyright notice and the following two paragraphs appear in all
;;; copies of this software.
;;; 
;;; IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY
;;; FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
;;; ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN IF
;;; THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY OF
;;; SUCH DAMAGE.
;;;
;;; THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES,
;;; INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
;;; MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE
;;; PROVIDED HEREUNDER IS ON AN "AS IS" BASIS, AND THE UNIVERSITY OF
;;; CALIFORNIA HAS NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES,
;;; ENHANCEMENTS, OR MODIFICATIONS.
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; $Id: gemm.lisp,v 1.2 2000/05/08 17:19:18 rtoy Exp $
;;;
;;; $Log: gemm.lisp,v $
;;; Revision 1.2  2000/05/08 17:19:18  rtoy
;;; Changes to the STANDARD-MATRIX class:
;;; o The slots N, M, and NXM have changed names.
;;; o The accessors of these slots have changed:
;;;      NROWS, NCOLS, NUMBER-OF-ELEMENTS
;;;   The old names aren't available anymore.
;;; o The initargs of these slots have changed:
;;;      :nrows, :ncols, :nels
;;;
;;; Revision 1.1  2000/04/14 00:11:12  simsek
;;; o This file is adapted from obsolete files 'matrix-float.lisp'
;;;   'matrix-complex.lisp' and 'matrix-extra.lisp'
;;; o Initial revision.
;;;
;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package "MATLISP")

(use-package "BLAS")
(use-package "LAPACK")
(use-package "FORTRAN-FFI-ACCESSORS")

(export '(gemm!
	  gemm))

(defgeneric gemm! (alpha a b beta c &optional job)
  (:documentation
"
  Syntax
  ======
  (GEMM! alpha a b beta c [job])

  Purpose
  =======
  Performs the GEneral Matrix Multiplication given by
               --      -      -

            C <- alpha * op(A) * op(B) + beta * C
     
  and returns C.

  alpha,beta are scalars and A,B,C are matrices.
  op(A) means either A or A'.

     JOB                    Operation
  ---------------------------------------------------
     :NN (default)      alpha * A * B + beta * C
     :TN                alpha * A'* B + beta * C
     :NT                alpha * A * B'+ beta * C
     :TT                alpha * A'* B'+ beta * C     

 Note
 ====
 Take caution when using GEMM! as follows:

           (GEMM! alpha a b beta b)

     or

          (GEMM! alpha a b beta a)

  The results may be unpredictable depending
  on the underlying DGEMM, ZGEMM routines
  from BLAS, ATLAS or LIBCRUFT.
"))

(defgeneric gemm (alpha a b beta c &optional job)
  (:documentation
"
  Syntax
  ======
  (GEMM alpha a b beta c [job])

  Purpose
  =======
  Performs the GEneral Matrix Multiplication given by
               --      -      -

             alpha * op(A) * op(B) + beta * C
     
  and returns the result in a new matrix.

  alpha,beta are scalars and A,B,C are matrices.
  op(A) means either A or A'.

     JOB                    Operation
  ---------------------------------------------------
     :NN (default)      alpha * A * B + beta * C
     :TN                alpha * A'* B + beta * C
     :NT                alpha * A * B'+ beta * C
     :TT                alpha * A'* B'+ beta * C     

"))

(defmethod gemm! :before ((alpha number) 
			  (a standard-matrix) 
			  (b standard-matrix)
			  (beta number) 
			  (c standard-matrix) 
			  &optional (job :NN))
  (let ((n-a (nrows a))
	(m-a (ncols a))
	(n-b (nrows b))
	(m-b (ncols b))
	(n-c (nrows c))
	(m-c (ncols c)))
    (declare (type fixnum n-a m-a n-b m-b n-c m-c))

    (case job
      (:nn t)
      (:tn (rotatef n-a m-a))
      (:nt (rotatef n-b m-b))
      (:tt (rotatef n-a m-a) (rotatef n-b m-b))
      (t (error "argument JOB to GEMM! is not recognized")))

    (if (not (and (= m-a n-b)
		  (= n-a n-c)
		  (= m-b m-c)))
	(error "dimensions of A,B,C given to GEMM! do not match"))))

(defmethod gemm! ((alpha double-float) 
		  (a real-matrix) 
		  (b real-matrix)
		  (beta double-float) 
		  (c real-matrix) 
		  &optional (job :nn))

  (let ((n (nrows c))
	(m (ncols c))
	(k (if (member job '(:NN NN :NT NT))
	       (ncols a)
	     (nrows a))))
    (declare (type fixnum n m k))
    (multiple-value-bind (job-a job-b lda ldb)
	 (case job
          (:NN (values "N" "N"  n k))
	  (:NT (values "N" "T"  n m))
	  (:TN (values "T" "N"  k k))
	  (:TT (values "T" "T"  k m))
	  (t (values)))

	 (declare (type fixnum lda ldb)
		  (type (string 1) job-a job-b))

	 (dgemm job-a     ; TRANSA
		job-b     ; TRANSB
		n         ; M
		m         ; N (LAPACK takes N,M opposite our convention)
		k         ; K
		alpha     ; ALPHA
		(store a) ; A
		lda       ; LDA
		(store b) ; B
		ldb       ; LDB
		beta      ; BETA
		(store c) ; C
		n )       ; LDC
 
	 c)))

(defmethod gemm! ((alpha real) 
		  (a real-matrix) 
		  (b real-matrix)
		  (beta real) 
		  (c real-matrix) 
		  &optional (job :nn))
  (gemm! (coerce alpha 'real-matrix-element-type)
	 a
	 b
	 (coerce beta 'real-matrix-element-type)
	 c
	 job))

(defvar *complex-alpha* (make-array 2 :element-type 'complex-matrix-element-type))
(defvar *complex-beta* (make-array 2 :element-type 'complex-matrix-element-type))

(defmethod gemm! ((alpha kernel::complex-double-float) 
		  (a complex-matrix) 
		  (b complex-matrix)
		  (beta kernel::complex-double-float) 
		  (c complex-matrix) 
		  &optional (job :nn))

  (let ((n (nrows c))
	(m (ncols c))
	(k (if (member job '(:NN NN :NT NT))
	       (ncols a)
	     (nrows a))))
    (declare (type fixnum n m k))
    (multiple-value-bind (job-a job-b lda ldb)
	 (case job
          (:NN (values "N" "N"  n k))
	  (:NT (values "N" "T"  n m))
	  (:TN (values "T" "N"  k k))
	  (:TT (values "T" "T"  k m))
	  (t (values)))

	 (declare (type fixnum lda ldb)
		  (type (string 1) job-a job-b))

	 (setf (aref *complex-alpha* 0) (realpart alpha))
	 (setf (aref *complex-alpha* 1) (imagpart alpha))
	 (setf (aref *complex-beta* 0) (realpart beta))
	 (setf (aref *complex-beta* 1) (imagpart beta))

	 (zgemm job-a     ; TRANSA
		job-b     ; TRANSB
		n         ; M
		m         ; N (LAPACK takes N,M opposite our convention)
		k         ; K
		*complex-alpha*  ; ALPHA
		(store a) ; A
		lda       ; LDA
		(store b) ; B
		ldb       ; LDB
		*complex-beta*      ; BETA
		(store c) ; C
		n )       ; LDC
 
	 c)))

(defmethod gemm! ((alpha number) 
		  (a complex-matrix) 
		  (b complex-matrix)
		  (beta number) 
		  (c complex-matrix) 
		  &optional (job :nn))
  (gemm! (complex-coerce alpha)
	 a
	 b
	 (complex-coerce beta)
	 c
	 job))


(defmethod gemm! ((alpha number) 
		  (a standard-matrix) 
		  (b standard-matrix)
		  (beta number) 
		  (c complex-matrix) 
		  &optional (job :NN))

  (let ((a (typecase a
	     (real-matrix (copy! a (make-complex-matrix-dim (nrows a) (ncols a))))
	     (complex-matrix a)
	     (t (error "argument A given to GEMM! is not a REAL-MATRIX or COMPLEX-MATRIX"))))
	(b (typecase b
	     (real-matrix (copy! b (make-complex-matrix-dim (nrows b) (ncols b))))
	     (complex-matrix b)
	     (t (error "argument B given to GEMM! is not a REAL-MATRIX or COMPLEX-MATRIX")))))

    (gemm! (complex-coerce alpha)
	   a
	   b
	   (complex-coerce beta)
	   c
	   job)))


;;;;;

(defmethod gemm :before ((alpha number) 
			 (a standard-matrix) 
			 (b standard-matrix)
			 (beta number) 
			 (c standard-matrix) 
			 &optional (job :NN))
  (let ((n-a (nrows a))
	(m-a (ncols a))
	(n-b (nrows b))
	(m-b (ncols b))
	(n-c (nrows c))
	(m-c (ncols c)))
    (declare (type fixnum n-a m-a n-b m-b n-c m-c))

    (case job
      (:nn t)
      (:tn (rotatef n-a m-a))
      (:nt (rotatef n-b m-b))
      (:tt (rotatef n-a m-a) (rotatef n-b m-b))
      (t (error "argument JOB to GEMM! is not recognized")))

    (if (not (and (= m-a n-b)
		  (= n-a n-c)
		  (= m-b m-c)))
	(error "dimensions of A,B,C given to GEMM! do not match"))))


(defmethod gemm ((alpha real) 
		 (a real-matrix) 
		 (b real-matrix)
		 (beta real) 
		 (c real-matrix) 
		 &optional (job :nn))

  (gemm! (coerce alpha 'real-matrix-element-type)
	 a
	 b
	 (coerce beta 'real-matrix-element-type)
	 (copy c)
	 job))


;; if all args are not real then at least one of them
;; is complex, so we need to call GEMM! with a complex C
(defmethod gemm ((alpha number) 
		 (a standard-matrix) 
		 (b standard-matrix)
		 (beta number) 
		 (c standard-matrix) 
		 &optional (job :NN))

  (let	((c (typecase c
	     (real-matrix (copy! c (make-complex-matrix-dim (nrows c) (ncols c))))
	     (complex-matrix (copy c))
	     (t (error "argument C given to GEMM is not a REAL-MATRIX or COMPLEX-MATRIX")))))

    (gemm! (complex-coerce alpha)
	   a
	   b
	   (complex-coerce beta)
	   c
	   job)))