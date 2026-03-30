;;; agent-shell-macext.el --- macOS extensions for agent-shell  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 realazy

;; Author: realazy
;; URL: https://github.com/cxa/agent-shell-macext
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (agent-shell "0.48.1"))

;; This package is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This package is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:
;;
;; `agent-shell-macext' provides macOS-specific enhancements for `agent-shell',
;; making it more comfortable to use on macOS.
;;

;;; Code:

(require 'agent-shell)

(declare-function agent-shell--get-files-context "agent-shell")
(declare-function agent-shell-insert "agent-shell")
(declare-function agent-shell--shell-buffer "agent-shell")
(declare-function agent-shell--dot-subdir "agent-shell")
(declare-function agent-shell-yank-dwim "agent-shell")
(declare-function agent-shell-cwd "agent-shell-project")

(defgroup agent-shell-macext nil
  "macOS extensions for `agent-shell'."
  :group 'agent-shell
  :prefix "agent-shell-macext-")

;;; Yank

(defcustom agent-shell-macext-file-copy-policy 'auto
  "Controls whether files are copied to .agent-shell/.macext/ before use.

`auto'           Copy only files that live outside the current project
                 directory, where the agent may lack read permission.
                 Files already inside the project are used as-is.

`always-copy'    Always copy every file to .agent-shell/.macext/,
                 regardless of where it lives.

`always-original' Never copy; always pass the original path to the agent."
  :type '(choice (const :tag "Auto (copy only if outside project)" auto)
                 (const :tag "Always copy" always-copy)
                 (const :tag "Always use original path" always-original))
  :group 'agent-shell-macext)

(defun agent-shell-macext--clipboard-file-paths ()
  "Return list of file paths from macOS clipboard (e.g. copied from Finder), or nil."
  (when (eq (window-system) 'ns)
    (condition-case nil
        (when-let ((output (with-temp-buffer
                             (when (zerop
                                    (call-process
                                     "osascript" nil t nil
                                     "-l" "JavaScript"
                                     "-e" "ObjC.import('AppKit'); \
var pb = $.NSPasteboard.generalPasteboard; \
var names = pb.propertyListForType('NSFilenamesPboardType'); \
if (names.isNil()) { '' } else { \
  var r = ''; \
  for (var i = 0; i < names.count; i++) { \
    r += ObjC.unwrap(names.objectAtIndex(i)) + '\\n'; \
  } r; }"))
                               (buffer-string)))))
          (seq-filter #'file-exists-p
                      (mapcar #'string-trim
                              (split-string output "\n" t))))
      (error nil))))

(defun agent-shell-macext--macext-dir ()
  "Return .agent-shell/.macext/ directory, creating it if needed."
  (agent-shell--dot-subdir ".macext"))

(defun agent-shell-macext--copy-to-macext-dir (file-path)
  "Copy FILE-PATH into .agent-shell/.macext/ and return the new path."
  (let* ((dest-dir (agent-shell-macext--macext-dir))
         (dest (expand-file-name (file-name-nondirectory file-path) dest-dir)))
    (copy-file file-path dest t)
    dest))

(defun agent-shell-macext--outside-project-p (file-path)
  "Return non-nil if FILE-PATH is outside the current project directory."
  (let ((project-dir (file-truename (agent-shell-cwd)))
        (file-truename (file-truename file-path)))
    (not (string-prefix-p (file-name-as-directory project-dir) file-truename))))

(defun agent-shell-macext--permission-allow-all-p ()
  "Return non-nil if agent-shell is configured to auto-approve all permissions.
This covers `agent-shell-permission-allow-always' and any equivalent handler."
  (eq agent-shell-permission-responder-function
      #'agent-shell-permission-allow-always))

(defun agent-shell-macext--resolve-file-path (file-path)
  "Return the path to use for FILE-PATH according to `agent-shell-macext-file-copy-policy'.

In `auto' mode, also checks whether the agent has blanket permission
(e.g. `agent-shell-permission-allow-always'), in which case copying is
unnecessary and the original path is used directly."
  (pcase agent-shell-macext-file-copy-policy
    ('always-copy     (agent-shell-macext--copy-to-macext-dir file-path))
    ('always-original file-path)
    ('auto            (if (or (agent-shell-macext--permission-allow-all-p)
                              (not (agent-shell-macext--outside-project-p file-path)))
                          file-path
                        (agent-shell-macext--copy-to-macext-dir file-path)))))

;; Inherit yank's `delete-selection' property so
;; `delete-selection-mode' replaces the active region on paste.
(put 'agent-shell-macext-yank 'delete-selection 'yank)
(defun agent-shell-macext-yank (&optional arg)
  "Enhanced yank for `agent-shell' on macOS.

Checks the clipboard in order:

1. NS file paths (e.g. files copied from Finder):
   - Images are inserted as inline image context.
   - Other files are copied to .agent-shell/.macext/ and their new
     paths are inserted as text.

2. Clipboard text that is an existing file path: the file is copied
   to .agent-shell/.macext/ and the new path is inserted.

3. Otherwise, fall back to `agent-shell-yank-dwim' (which handles
   raw clipboard image data), then plain `yank'."
  (interactive "*P")
  (let* ((ns-files (agent-shell-macext--clipboard-file-paths))
         (kill-text (ignore-errors (current-kill 0 t)))
         (text-as-file (when (and kill-text (not ns-files))
                         (let ((trimmed (string-trim kill-text)))
                           (when (file-exists-p trimmed) trimmed)))))
    (cond
     (ns-files
      (agent-shell-macext--insert-files ns-files))
     (text-as-file
      (agent-shell-macext--insert-files (list text-as-file)))
     (t
      (agent-shell-yank-dwim arg)))))

;;; Drag and drop

(defun agent-shell-macext--insert-files (file-paths)
  "Insert FILE-PATHS into the agent-shell buffer, same as yank."
  (let* ((resolved (mapcar #'agent-shell-macext--resolve-file-path file-paths))
         (images (seq-filter #'image-supported-file-p resolved))
         (others (seq-remove #'image-supported-file-p resolved))
         (shell-buffer (agent-shell--shell-buffer)))
    (when resolved
      (agent-shell-insert
       :text (agent-shell--get-files-context :files resolved)
       :shell-buffer shell-buffer))))

(defun agent-shell-macext--dnd-handler (url _action)
  "Handle a single drag-and-drop file URL into an agent-shell buffer."
  (require 'dnd)
  (when-let ((file (dnd-get-local-file-name url t)))
    (agent-shell-macext--insert-files (list file))
    'private))

(defun agent-shell-macext--dnd-multi-handler (urls _action)
  "Handle multiple drag-and-drop file URLs into an agent-shell buffer."
  (require 'dnd)
  (let ((files (delq nil (mapcar (lambda (url) (dnd-get-local-file-name url t)) urls))))
    (when files
      (agent-shell-macext--insert-files files)
      'private)))

(put 'agent-shell-macext--dnd-multi-handler 'dnd-multiple-handler t)

(defun agent-shell-macext--setup-dnd ()
  "Set up drag-and-drop handlers for the current agent-shell buffer."
  (let ((handler (if (>= emacs-major-version 30)
                     #'agent-shell-macext--dnd-multi-handler
                   #'agent-shell-macext--dnd-handler)))
    (setq-local dnd-protocol-alist
                (append (list (cons "^file:///" handler)
                              (cons "^file:/[^/]" handler)
                              (cons "^file:[^/]" handler))
                        dnd-protocol-alist))))

;;; Setup

;;;###autoload
(defun agent-shell-macext-setup ()
  "Set up macOS extensions for `agent-shell'.
Intended for use as a hook on `agent-shell-mode-hook'."
  (unless (eq system-type 'darwin)
    (user-error "agent-shell-macext is intended for macOS only"))
  (define-key agent-shell-mode-map [remap yank] #'agent-shell-macext-yank)
  (agent-shell-macext--setup-dnd))

(provide 'agent-shell-macext)

;;; agent-shell-macext.el ends here
