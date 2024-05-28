;;; wyrm-mode.el --- Major mode for wyrm script files -*- lexical-binding: t; -*-

;; Copyright (c) 2020 Craig Becker.

;; Author: Craig Becker (http://github.com/wirefish)
;;
;; Version: 0.1
;; Package-Requires: ((emacs "26.3"))
;; Keywords: languages wyrm
;; URL: https://github.com/wirefish/wyrm

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Major mode for wyrm script files.

;;; Code:

(defconst wyrm-identifier-re "[_a-zA-Z][_a-zA-Z0-9]*")

(defconst wyrm-symbol-re (concat "'" wyrm-identifier-re))

(defconst wyrm-name-re wyrm-identifier-re)

(defconst wyrm-def-re
  "^ *\\(entity\\|location\\|region\\|heritage\\|event\\|command\\|quest\\|skill\\|extend\\) +")

(defconst wyrm-fdef-re
  "^ *\\(after\\|allow\\|before\\|when\\|func\\) +")

(defconst wyrm-fname-re (concat "\\(" wyrm-identifier-re "\\)("))

(defconst wyrm-end-block-re " *}"
  "Regexp matching a line that ends a block.")

(defconst wyrm-basic-offset 2)

(setq wyrm-font-lock-keywords
      (let* (
             ;; define several category of keywords
             (x-keywords '("await" "continue" "else" "if" "import" "for"
                           "return" "self" "to" "var"))
             (x-constants '("false" "true" "nil"))

             ;; generate regex string for each category of keywords
             (x-keywords-regexp (regexp-opt x-keywords 'symbols))
             (x-constants-regexp (regexp-opt x-constants 'symbols)))
        `(
          (,x-constants-regexp . font-lock-constant-face)
          (,x-keywords-regexp . font-lock-keyword-face)
          (,wyrm-symbol-re . font-lock-constant-face)
          (,wyrm-def-re (1 font-lock-keyword-face)
                        (,wyrm-name-re nil nil (0 font-lock-type-face)))
          (,wyrm-fdef-re (1 font-lock-keyword-face)
                         (,wyrm-fname-re nil nil (1 font-lock-function-name-face))))))

(defvar wyrm-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "\"" 'wyrm-electric-quote)
    (define-key map "{" 'wyrm-electric-brace)
    (define-key map "\M-q" 'wyrm-fill-text)
    map)
  "Keymap used in `wyrm-mode' buffers.")

(defconst wyrm-mode-syntax-table
  (let ((table (copy-syntax-table prog-mode-syntax-table)))
    (modify-syntax-entry ?\/ ". 124" table)
    (modify-syntax-entry ?\* ". 23b" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?\' "'" table)
    table))

(defun wyrm-innermost-paren (state)
  (nth 1 state))

(defun wyrm-inside-string? (state)
  (nth 3 state))

(defun wyrm-start-of-string (state)
  (nth 8 state))

(defun wyrm-compute-indentation ()
  (save-excursion
    (beginning-of-line)
    (let ((state (syntax-ppss)))
      (cond
       ;; If this line is the end of a block, indent it to the same level as the
       ;; line where the block began.
       ((looking-at wyrm-end-block-re)
        (goto-char (wyrm-innermost-paren state))
        (current-indentation))
       ;; If inside a multiline string, indent from the start of the string.
       ((wyrm-inside-string? state)
        (progn
          (goto-char (wyrm-start-of-string state))
          (+ (current-indentation) wyrm-basic-offset)))
       ;; Otherwise, look for the closest "{[(" and indent from there.
       ((wyrm-innermost-paren state)
        (goto-char (wyrm-innermost-paren state))
        (if (char-equal (char-after) ?\{)
            (+ (current-indentation) wyrm-basic-offset)
          (+ (current-column) 1)))
       (t 0)))))

(defun wyrm-electric-quote (arg)
  "Insert \" and, if the previous two characters are also \", insert a
newline and the terminator for a multiline string."
  (interactive "*P")
  (self-insert-command (prefix-numeric-value arg))
  (when (save-excursion
          (backward-char 3)
          (and (not (wyrm-inside-string? (syntax-ppss)))
               (looking-at "\"\"\"")))
    (save-excursion
      (newline)
      (insert "\"\"\"")
      (wyrm-indent-line))
    (newline-and-indent)))

(defun wyrm-electric-brace (arg)
  (interactive "*P")
  (let ((prev (char-before)))
    (self-insert-command (prefix-numeric-value arg))
    (when (char-equal prev ?\s)
      (save-excursion
        (newline)
        (insert-char ?} (prefix-numeric-value arg))
        (wyrm-indent-line))
      (newline-and-indent))))

(defun wyrm-indent-line ()
  (interactive "*")
  (let ((ci (current-indentation))
        (cc (current-column))
        (need (wyrm-compute-indentation)))
    (save-excursion
      (beginning-of-line)
      (delete-horizontal-space)
      (indent-to need)))
      (if (< (current-column) (current-indentation))
          (forward-to-indentation 0)))

(defun wyrm-fill-text ()
  (interactive "*")
  (let ((state (syntax-ppss)))
    (when (wyrm-inside-string? state)
      (message "foo")
      (save-excursion
        (goto-char (wyrm-start-of-string state))
        (when (looking-at "\"\n")
          (forward-line 1)
          (let ((start (point)))
            (when (search-forward "\"\"\"")
              (beginning-of-line)
              (fill-region start (point)))))))))

(define-derived-mode wyrm-mode prog-mode "Wyrm"
  "Major mode for editing wyrm script files."
  (setq font-lock-defaults '((wyrm-font-lock-keywords)))
  (setq tab-width wyrm-basic-offset)
  (setq indent-line-function 'wyrm-indent-line)
  (add-to-list 'electric-indent-chars ?\}))

(provide 'wyrm-mode)
