# warp
Highlight and locate NONL non-local entanglements in comments and strings.

It's very easy to wind up with entangled, interdependent implementations.
Without careful tracking, 
one can quickly wind up with technical debt that is thoroughly wedged, 
and be unable to straight-forwardly locate all the necessary changes
to replace the implementation with something better.

To fix this, consider the Non-Local Entanglement comment flag. 
Just like one might normally mark code with `TODO:` or `FIXME:`,
one can start a comment with `NONL:` and some identifying string.
This identifier is then used to mark each entangled piece of code.
For example:

``` emacs-lisp
;; NONL: Terrible Kludge
(progn 
  (do-something-terrible)
  (do-it-fast))
```

With `warp-mode` enabled, Emacs will highlight `NONL` in constant face,
and turn `Terrible Kludge` into a button that launches a search for that NONL,
across your entire project. 

`warp` depends on `projectile` and `rg`, 
and can be added to Doom Emacs with the following snippets:

``` emacs-lisp $DOOMDIR/packages.el
(package! rg)

(package! warp
:recipe (:host github :repo "seylerius/warp"))
```

``` emacs-lisp $DOOMDIR/config.el
(use-package! rg
  :config
  (setq rg-group-result nil)
  :commands (rg))

(use-package! warp
  :hook (prog-mode . warp-mode))
```

