;;; agent-shell-macext-test.el --- Tests for agent-shell-macext  -*- lexical-binding: t; -*-

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'agent-shell-macext)

(ert-deftest agent-shell-macext-setup-remaps-viewport-yank ()
  "Set up the enhanced yank command in viewport edit buffers."
  (let ((shell-binding
         (lookup-key agent-shell-mode-map [remap yank]))
        (viewport-binding
         (lookup-key agent-shell-viewport-edit-mode-map [remap yank])))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-shell-macext--setup-dnd)
                   #'ignore)
                  ((symbol-function 'agent-shell-macext--setup-notifications)
                   #'ignore))
          (agent-shell-macext-setup)
          (should
           (eq (lookup-key agent-shell-viewport-edit-mode-map [remap yank])
               #'agent-shell-macext-yank)))
      (define-key agent-shell-mode-map [remap yank] shell-binding)
      (define-key agent-shell-viewport-edit-mode-map [remap yank]
                  viewport-binding))))

(provide 'agent-shell-macext-test)

;;; agent-shell-macext-test.el ends here
