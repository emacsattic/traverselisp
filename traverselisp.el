;;; traverse-lisp.el -- elisp implementations of rgrep, grep-find, grep, etc...

;; Author: Thierry Volpiatto

;; Copyright (C) 2008 Thierry Volpiatto
;;
;; this file is NOT part of GNU Emacs
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3 of
;; the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be
;; useful, but WITHOUT ANY WARRANTY; without even the implied
;; warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
;; PURPOSE.  See the GNU General Public License for more details.

;; You should have received a copy of the GNU General Public
;; License along with this program; if not, write to the Free
;; Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301 USA


;; Comments:
;; ========
;; This code is EXPERIMENTAL and NOT FINISHED, if you want something
;; stable, use the python implementation (see README)

;; However, it's actually working fine, if you want to test it,
;; you need only this file.

;; Install:
;; =======
;; (require 'traversepurelisp)
;; (setq max-lisp-eval-depth 40000)

;; Usage:
;; =====
;; M-x traverse-deep-rfind
;; Use customize to configure or setq differents variables.


;;; Code:
(require 'derived)
(eval-when-compile (require 'cl))

(defvar traversedir-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [?q] 'traverse-quit)
    map)
  "Keymap used for traversedir commands.")

(define-derived-mode traversedir-mode text-mode "traversedir"
  "Major mode to search regexp in files recursively.

Special commands:
\\{traversedir-mode-map}")


(defun traverse-quit ()
  "Quit and kill traverse buffer"
  (interactive)
  (quit-window t))

(defgroup traversedir nil
  "Mode to search recursively regex like grep-find"
  :prefix "traversedir"
  :group 'text)

(defcustom traverse-ignore-files
  '(".elc" ".pyc"
    ".orig" ".bz2"
    ".gz" ".zip"
    ".vdi" ".doc"
    ".jpg" ".avi"
    ".jpeg" ".png"
    ".xpm" ".jar"
    ".pbm" ".gif"
    ".xls" ".ppt"
    ".mdb" ".adp"
    "TAGS" ".tiff"
    ".pdf" ".dvi"
    ".xbm")
  "Files we want to ignore (extensions)"
  :group 'traversedir
  :type '(repeat string))

(defcustom traverse-ignore-dirs
  '(".hg" ".svn"
    "RCS" ".bzr"
    ".git" ".VirtualBox"
    ".arch-ids" "CVS"
    "{arch}")
  "Directory we don't want to search in"
  :group 'traversedir
  :type '(repeat string))

(defcustom traverse-length-line
  45
  "Length of the line displayed"
  :group 'traversedir
  :type 'integer)

(defcustom traverse-file-function
  'traverse-tv-file-process
  "Default function to use to process files"
  :group 'traversedir
  :type 'symbol)

(defvar traverse-version "0.1")

(defun traverse-lisp-version ()
  (interactive)
  (message "traverse-lisp-version-%s" traverse-version))

;;; Main backend functions

;;;###autoload
(defmacro tv-list-directory (dirname &optional abs)
  "Use directory-files without these \".\" \"..\".
If abs is non-nil use absolute path.
Check a second time with mapcar if we have no \".\" or \"..\"
in case we have a directory with crappy files.
This to avoid infinite loop in walk"
  `(let ((clean-dir (cddr (directory-files ,dirname ,abs))))
    (mapcar #'(lambda (x)
                (if (and (not (equal (file-name-nondirectory x)
                                     "."))
                         (not (equal (file-name-nondirectory x)
                                     "..")))
                    x))
            clean-dir)))


(defun file-compressed-p (fname)
  (let ((ext (file-name-extension fname)))
    (cond ((equal ext "gz")
           t)
          ((equal ext "bz2")
           t)
          ((equal ext "zip")
           t)
          (t nil))))


;;;###autoload
(defun tv-walk-directory (dirname file-fn &optional exclude-files exclude-dirs)
    "Walk through dirname and use file-fn function
on each file found.
`dirname' ==> we start in this directory
`file-fn' ==> function to apply to FILES
`excludes-files' ==> list of .ext to ignore  
`exclude-dirs' ==> list of directory to ignore
"
    (labels
        ((walk (name)
           (cond ((and (file-directory-p name) ;; DIR PROCESSING
                       (not (file-symlink-p name))) ;; don't follow symlinks
                  (if exclude-dirs
                      (dolist (x (tv-list-directory name t))
                        (if x ;; be sure x is a string and not nil
                            (unless (member (file-name-nondirectory x) exclude-dirs)
                              (walk x)))) ;; Return to TOP and take the good cond
                      (dolist (x (tv-list-directory name t))
                        (if x
                            (walk x))))) ;; Return to TOP and take the good cond
                 ((and (file-regular-p name) ;; FILE PROCESSING
                       (not (file-symlink-p name))) ;; don't follow symlinks
                  (if exclude-files
                      (unless (member (file-name-extension name t) exclude-files)
                        (funcall file-fn name))
                      (funcall file-fn name))))))
      (walk (expand-file-name dirname))))


;;;###autoload
(defmacro tv-readlines (file &optional delete-empty-lines)
  "Return a list where elements are the lines of a file
\\(emulate object.readlines() of python)"
  `(let* ((my-string (with-temp-buffer
                       (insert-file-contents ,file)
                       (buffer-string)))
          (my-read-list (split-string my-string "\n")))
     (when ,delete-empty-lines
       (dolist (i my-read-list)
         (when (equal i "")
           (delete i my-read-list))))
     my-read-list))


;;;###autoload
(defmacro tv-find-all-regex-in-file (regex file)
  "Return a list with elements of the form :
'(matched-line char-pos line-pos)
Example:
,----
| ELISP> (tv-find-all-regex-in-file \"ligne\" \"~/toto\")
| ((\"avec une premiere ligne\" 62 2)
|  (\"une deuxieme ligne\" 93 3)
|  (\"une troisieme ligne\" 126 4))
`----
"
  `(let ((infile-list (tv-readlines ,file))
        (outfile-list nil)
        (count-line 0)
        (count-char 0)
        (pos-match)
        (tmp-count-char 0))
    (dolist (i infile-list)
      (setq count-line (+ count-line 1))
      (setq pos-match (string-match ,regex i)) 
      (when pos-match
        (setq tmp-count-char (+ count-char (- (+ 1 (length i)) pos-match)))
        (add-to-list 'outfile-list `(,i ,tmp-count-char ,count-line) t))
      (setq count-char (+ count-char (if (equal i "")
                                         1
                                         (+ 1 (length i))))))
    outfile-list))


;;;###autoload
(defun tv-find-first-regex-in-file (regex file)
  "Stop at the first match of regex and return line
as string"
  (let ((file-list (tv-readlines file)))
    (catch 'break
      (dolist (i file-list)
        (when (string-match regex i)
          (throw 'break
            i))))))


;; (defun traverse-find-in-file (regexp file)
;;   (interactive "sRegexp: \nfFileName: "))


;; TODO if permission is denied do the right thing
(defvar traverse-count-occurences -1)

;;;###autoload
(defun traverse-tv-file-process (regex fname)
  "Default function to process files  and insert matched lines
in *traverse-lisp* buffer"
  (let ((matched-lines (tv-find-all-regex-in-file regex fname))
        (form-line))
    (when matched-lines
      (dolist (i matched-lines)
        (and (insert-button (format "[%s]" fname)
                            'action #'(lambda (button)
                                        (let* ((list-line (split-string (thing-at-point 'line)))
                                               (nline (nth 1 list-line))
                                               (regex)
                                               (fname (button-label (button-at (point)))))
                                          (save-excursion
                                            (goto-char (point-min))
                                            (when (re-search-forward "^Found ")
                                              (end-of-line)
                                              (beginning-of-sexp)
                                              (setq regex (thing-at-point 'sexp))))
                                          (save-excursion
                                            (setq fname (replace-regexp-in-string "\\[" "" fname))
                                            (setq fname (replace-regexp-in-string "\\]" "" fname))
                                            (find-file-other-window fname) 
                                            (goto-line (string-to-number nline))
                                            (setq case-fold-search t)
                                            (beginning-of-line)
                                            (when (re-search-forward regex nil nil)
                                              (beginning-of-sexp) 
                                              (highlight-regexp (thing-at-point 'sexp))
                                              (sit-for 2)
                                              (unhighlight-regexp (thing-at-point 'sexp))))))
                            'face "hi-green")
             (insert (concat " "
                             (int-to-string (third i))
                             " :"
                             (replace-regexp-in-string "^ *" ""
                                                       (if
                                                        (> (length (first i))
                                                           traverse-length-line)
                                                        (substring (first i)
                                                                   0
                                                                   traverse-length-line)
                                                        (first i)))
                             "\n"))))
      (setq traverse-count-occurences (+ traverse-count-occurences
                                         (length matched-lines))))))


;;;###autoload
(defun traverse-deep-rfind (tree regexp &optional only)
  "Main function that call walk, if only is omitted it
will be set as nil and search will be proceeded on all files
except on files that are in `traverse-ignore-files'"
  (interactive "DTree: \nsRegexp: \nsCheckOnly: ")
  (set-buffer (get-buffer-create "*traverse-lisp*"))
  (erase-buffer)
  (hi-lock-mode)
  (goto-char (point-min))
  (traversedir-mode)
  (insert " *Traverse-lisp-output*\n\n\n")
  (highlight-regexp " \\*Traverse-lisp-output\\*$" "hi-pink")
  (display-buffer "*traverse-lisp*")
  (insert  "Wait Lisp searching...\n\n")
  (sit-for 1)
  (let ((init-time (cadr (current-time))))
    (unwind-protect
         (tv-walk-directory tree
                            #'(lambda (y)
                                (if (equal only "")
                                    (setq only nil))
                                (if only
                                    (when (equal (file-name-extension y t)
                                                 only)
                                      (funcall traverse-file-function regexp y))
                                    (funcall traverse-file-function regexp y))
                                (message "%s [Matches] for %s in [%s]"
                                         (if (>= traverse-count-occurences 1)
                                             traverse-count-occurences
                                             0)
                                         regexp
                                         y))
                            traverse-ignore-files
                            traverse-ignore-dirs)
      (setq traverse-count-occurences (if (< traverse-count-occurences 0)
                                          0
                                          traverse-count-occurences))
      (if (eq traverse-count-occurences 0)
          (progn
            (goto-char (point-min))
            (when (re-search-forward "^Wait")
              (beginning-of-line)
              (kill-line)
              (insert "Oh!No! Nothing found!")))
          (goto-char (point-min))
          (when (re-search-forward "^Wait")
            (beginning-of-line)
            (kill-line)
            (insert (format "Found %s occurences for %s:\n"
                            traverse-count-occurences
                            regexp))))
      (message "%s Occurences found for %s in %s seconds"
               traverse-count-occurences
               regexp
               (- (cadr (current-time)) init-time))
    (highlight-regexp regexp) 
    (setq traverse-count-occurences -1))))
    
    
(provide 'traverselisp)

;;; end of file

  