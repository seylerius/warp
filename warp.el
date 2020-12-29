;;; warp.el --- description -*- lexical-binding: t; -*-
;;
;; Copyright (C) 2020 Sable Seyler
;;
;; Author: Sable Seyler <http://github.com/seylerius>
;; Maintainer: Sable Seyler <sable@seyleri.us>
;; Created: December 29, 2020
;; Modified: December 29, 2020
;; Version: 0.1.0
;; Keywords:
;; Homepage: https://github.com/seylerius/warp
;; Package-Requires: ((emacs 27.1) (cl-lib "0.5"))
;;
;; This file is not part of GNU Emacs.
;;
;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.
;;
;;
;;; Commentary:
;;
;; Highlight and locate NONL non-local entanglements in comments and strings.
;;
;; You can either explicitly turn on `warp-mode' in specific buffers or use the
;; global variant `global-warp-mode', which enables the local mode based on each
;; buffer's major-mode and the options `warp-include-modes' and
;; `warp-exclude-modes'. By default, `warp-mode' is enabled for all buffers
;; whose major-mode derive from either `prog-mode'.
;;
;; Non-Local entanglements, indicated by a comment containing `NONL:' followed
;; by a text key, are used to declare that a piece of code depends on the
;; implementation consistency of one or more different pieces of code also
;; marked with that same key. When enabled, `warp-mode' will turn each such line
;; into a button, clickable with `mouse-2', that initiates a project-wide search
;; for all other locations with the same key.
;;
;; Substantial inspiration and some code borrowed from Jonas Bernoulli's
;; excellent `hl-todo-mode', which demonstrated quite well how to add highlights
;; to existing modes and detect whether one is currently in a comment or string.
;;
;;; Code:
(require 'rx)
(require 'cl-lib)
(require 'rg)
(require 'projectile)

(defgroup warp nil
  "Highlight and locate NONL non-local entanglements in comments and strings."
  :group 'font-lock-extra-types)

(defcustom warp-include-modes '(prog-mode)
  "Major-modes in which `warp-mode' is activated."
  :group 'warp
  :type '(repeat function))

(defcustom warp-exclude-modes '()
  "Major-modes in which `warp-mode' is not activated."
  :group 'warp
  :type '(repeat function))

(defvar warp--syntax-table (copy-syntax-table text-mode-syntax-table))

(defvar warp-mode-map (make-sparse-keymap)
  "Keymap for `warp-mode'.")

(defun warp--inside-comment-or-string-p ()
  "Check whether point is inside a comment or string."
  (nth 8 (syntax-ppss)))

(defconst warp--non-local-regexp
  (rx-to-string '(seq (group-n 1 "NONL:") (* space) (group-n 2 (* not-newline)))))

(defun warp--search (&optional regexp bound backward)
  "Search (forward unless BACKWARD non-nil) to BOUND for REGEXP."
  (unless regexp
    (setq regexp warp--non-local-regexp))
  (cl-block nil
    (while (let ((case-fold-search nil))
             (with-syntax-table warp--syntax-table
               (funcall (if backward #'re-search-backward #'re-search-forward)
                        regexp bound t)))
      (cond ((warp--inside-comment-or-string-p)
             (cl-return t))
            ((and bound (funcall (if backward #'<= #'>=) (point) bound))
             (cl-return nil))))))

(defvar warp--keywords '(((lambda (bound) (warp--search nil bound))
                          (1 font-lock-constant-face t t)
                          (2 font-lock-string-face t t)))
  "Keyword matcher for `warp-mode'.")

(defun warp--setup ()
  "Initialize font-lock keywords and hook."
  (add-hook! 'after-save-hook :local #'warp--add-buttons)
  (font-lock-add-keywords nil warp--keywords))

(defun warp--unsetup ()
  "Clear warp setup details."
  (remove-hook! 'after-save-hook :local #'warp--add-buttons)
  (font-lock-remove-keywords nil warp--keywords))

(defun warp--rg-nonl-regexp (identifier)
  "Generate a ripgrep regexp matching the Non-Local key IDENTIFIER."
  (concat "NONL:[ \\t\\f]*" identifier))

(defun warp--call-ripgrep (identifier)
  "Call ripgrep to locate the Non-Local key IDENTIFIER."
  (let ((rg-group-result nil))
    (rg-run
     (warp--rg-nonl-regexp identifier)
     "everything"
     (or (projectile-project-root) default-directory)
     nil nil
     '("-n" "-H" "--no-heading"))))

(defun warp--locate (button)
  "Call ripgrep for the Non-Local key in BUTTON."
  (warp--call-ripgrep (button-label button)))

(define-button-type 'warp-button
  'action #'warp--locate
  'help-echo "mouse-2, RET: Locate instances of this Non-Local entanglement key"
  'supertype 'button)

;;;###autoload
(define-minor-mode warp-mode
  "Highlight and locate NONL non-local entanglements in comments and strings."
  :lighter ""
  :keymap warp-mode-map
  :group 'warp
  (if warp-mode
      (warp--setup)
    (warp--unsetup))
  (when font-lock-mode
    (save-excursion
      (goto-char (point-min))
      (while (warp--search)
        (save-excursion
          (font-lock-fontify-region (match-beginning 0) (match-end 0) nil)))
      (goto-char (point-min))
      (while (warp--search)
        (save-excursion
          (make-button (match-beginning 2) (match-end 2) 'type 'warp-button))))))

;;;###autoload
(define-globalized-minor-mode global-warp-mode
  warp-mode warp--turn-on-mode-if-desired)

(defun warp--turn-on-mode-if-desired ()
  "Check for whether we're in a desired mode and turn on `warp-mode' if so."
  (when (and (apply #'derived-mode-p warp-include-modes)
             (not (apply #'derived-mode-p warp-exclude-modes))
             (not (bound-and-true-p enriched-mode)))
    (warp-mode 1)))

(defun warp--add-buttons ()
  "Hook to add Warp buttons post-change, searching across LEN from BEG to END."
  (if warp-mode
      (save-excursion
        (goto-char (point-min))
        (while (warp--search)
          (save-excursion
            (make-button (match-beginning 2) (match-end 2) 'type 'warp-button))))))

(provide 'warp)
;;; warp.el ends here
