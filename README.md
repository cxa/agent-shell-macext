# agent-shell-macext

macOS-specific enhancements for [agent-shell](https://github.com/xenodium/agent-shell).

## Features

### Enhanced `C-y` (yank)

Pressing `C-y` in an agent-shell buffer is context-aware on macOS:

- **Files copied from Finder** — inserts them as `@file` references. Images are shown as inline previews; other files appear as clickable links.
- **Clipboard text that is a file path** — same as above.
- **Raw image data on clipboard** — falls back to agent-shell's built-in handler.
- **Anything else** — normal yank.

### Drag and drop

Dragging files from Finder (or any app) into an agent-shell buffer works identically to `C-y`.

### Smart file copy policy

Files referenced from outside the project directory may not be readable by the agent due to macOS permissions. `agent-shell-macext` handles this transparently.

Controlled by `agent-shell-macext-file-copy-policy`:

| Value | Behavior |
|---|---|
| `auto` *(default)* | Copy files that are outside the project to `.agent-shell/.macext/`. Skip copying if the agent has blanket permissions (e.g. `agent-shell-permission-allow-always`) or if the file is already inside the project. |
| `always-copy` | Always copy every file to `.agent-shell/.macext/`. |
| `always-original` | Always use the original path as-is. |

## Requirements

- Emacs 29.1+
- [agent-shell](https://github.com/xenodium/agent-shell) 0.48.1+
- macOS (NS window system)

## Installation

### package-vc (Emacs 29+)

```elisp
(use-package agent-shell-macext
  :vc (:url "https://github.com/cxa/agent-shell-macext")
  :hook (agent-shell-mode . agent-shell-macext-setup)
  :custom
  (agent-shell-macext-file-copy-policy 'auto)) ; auto, always-copy, always-original
```

### Manual

Clone this repo and add it to your load path:

```elisp
(add-to-list 'load-path "/path/to/agent-shell-macext")
(require 'agent-shell-macext)
(setq agent-shell-macext-file-copy-policy 'auto) ; auto, always-copy, always-original
(add-hook 'agent-shell-mode-hook #'agent-shell-macext-setup)
```
