;;; org-static-blog.el --- a simple org-mode based static blog generator

;; Author: Bastian Bechtold
;; URL: https://github.com/bastibe/org-static-blog
;; Version: 1.0.4
;; Package-Requires: ((emacs "24.3"))

;;; Commentary:

;; Static blog generators are a dime a dozen. This is one more, which
;; focuses on being simple. All files are simple org-mode files in a
;; directory. The only requirement is that every org file must have a
;; #+TITLE and a #+DATE.

;; This file is also available from marmalade and melpa-stable.

;; Set up your blog by customizing org-static-blog's parameters, then
;; call M-x org-static-blog-publish to render the whole blog or
;; M-x org-static-blog-publish-file filename.org to render only only
;; the file filename.org.

;; Above all, I tried to make org-static-blog as simple as possible.
;; There are no magic tricks, and all of the source code is meant to
;; be easy to read, understand and modify.

;; If you have questions, if you find bugs, or if you would like to
;; contribute something to org-static-blog, please open an issue or
;; pull request on Github.

;; Finally, I would like to remind you that I am developing this
;; project for free, and in my spare time. While I try to be as
;; accomodating as possible, I can not guarantee a timely response to
;; issues. Publishing Open Source Software on Github does not imply an
;; obligation to *fix your problem right now*. Please be civil.

;;; Code:

(require 'ox-html)

(defgroup org-static-blog nil
  "Settings for a static blog generator using org-mode"
  :version "1.0.4"
  :group 'applications)

(defcustom org-static-blog-publish-url "https://example.com/"
  "URL of the blog."
  :group 'org-static-blog)

(defcustom org-static-blog-publish-title "Example.com"
  "Title of the blog."
  :group 'org-static-blog)

(defcustom org-static-blog-publish-directory "~/blog/"
  "Directory where published HTML files are stored."
  :group 'org-static-blog)

(defcustom org-static-blog-posts-directory "~/blog/posts/"
  "Directory where published ORG files are stored.
When publishing, posts are rendered as HTML, and included in the
index, archive, and RSS feed."
  :group 'org-static-blog)

(defcustom org-static-blog-drafts-directory "~/blog/drafts/"
  "Directory where unpublished ORG files are stored.
When publishing, draft are rendered as HTML, but not included in
the index, archive, or RSS feed."
  :group 'org-static-blog)

(defcustom org-static-blog-index-file "index.html"
  "File name of the blog landing page.
The index page contains the most recent
`org-static-blog-index-length` full-text posts."
  :group 'org-static-blog)

(defcustom org-static-blog-index-length 5
  "Number of articles to include on index page."
  :group 'org-static-blog)

(defcustom org-static-blog-archive-file "archive.html"
  "File name of the list of all blog entries.
The archive page lists all posts as headlines."
  :group 'org-static-blog)

(defcustom org-static-blog-tags-file "tags.html"
  "File name of the list of all blog entries by tag.
The tags page lists all posts as headlines."
  :group 'org-static-blog)

(defcustom org-static-blog-enable-tags nil
  "Show tags below posts, and generate tag pages."
  :group 'org-static-blog)

(defcustom org-static-blog-rss-file "rss.xml"
  "File name of the RSS feed."
  :group 'org-static-blog)

(defcustom org-static-blog-page-header ""
  "HTML to put in the <head> of each page."
  :group 'org-static-blog)

(defcustom org-static-blog-page-preamble ""
  "HTML to put before the content of each page."
  :group 'org-static-blog)

(defcustom org-static-blog-page-postamble ""
  "HTML to put after the content of each page."
  :group 'org-static-blog)

;;;###autoload
(defun org-static-blog-publish ()
  "Render all blog entries, the index, archive, and RSS feed.
Only blog entries that changed since the HTML was created are
re-rendered."
  (interactive)
  (let ((drafts (org-static-blog-get-draft-filenames))
        (rebuild nil))
    (dolist (file (append (org-static-blog-get-post-filenames)
                          drafts))
      (when (org-static-blog-needs-publishing-p file)
        (if (not (member file drafts))
            (setq rebuild t))
        (org-static-blog-publish-file file)))
    (when rebuild
      (org-static-blog-assemble-index)
      (org-static-blog-assemble-rss)
      (org-static-blog-assemble-archive)
      (if org-static-blog-enable-tags
          (org-static-blog-assemble-tags)))))

(defun org-static-blog-needs-publishing-p (post-filename)
  "Check whether POST-FILENAME was changed since last render."
  (let ((pub-filename
         (org-static-blog-matching-publish-filename post-filename)))
    (not (and (file-exists-p pub-filename)
              (file-newer-than-file-p pub-filename post-filename)))))

(defun org-static-blog-matching-publish-filename (post-filename)
  "Generate HTML file name for entry POST-FILENAME."
  (concat org-static-blog-publish-directory
          (file-name-base post-filename)
          ".html"))

(defun org-static-blog-get-post-filenames ()
  "Returns a list of all posts."
  (directory-files
   org-static-blog-posts-directory t ".*\\.org$" nil))

(defun org-static-blog-get-draft-filenames ()
  "Returns a list of all drafts."
  (directory-files
   org-static-blog-drafts-directory t ".*\\.org$" nil))

;; This macro is needed for many of the following functions.
(defmacro org-static-blog-with-find-file (file &rest body)
  "Executes BODY within a new buffer that contains FILE.
The buffer is disposed after the macro exits (unless it already
existed before)."
  `(save-excursion
     (let ((buffer-existed (get-buffer (file-name-nondirectory ,file)))
           (buffer (find-file ,file))
           (result nil))
       (setq result (progn ,@body))
       (switch-to-buffer buffer)
       (save-buffer)
      (unless buffer-existed
        (kill-buffer buffer))
      result)))

(defun org-static-blog-get-date (post-filename)
  "Extract the `#+date:` from entry POST-FILENAME."
  (with-temp-buffer
    (insert-file-contents post-filename)
    (goto-char (point-min))
    (search-forward-regexp "^\\#\\+date:[ ]*<\\([^]>]+\\)>$")
    (date-to-time (match-string 1))))

(defun org-static-blog-get-title (post-filename)
  "Extract the `#+title:` from entry POST-FILENAME."
  (with-temp-buffer
    (insert-file-contents post-filename)
    (goto-char (point-min))
    (search-forward-regexp "^\\#\\+title:[ ]*\\(.+\\)$")
    (match-string 1)))

(defun org-static-blog-get-tags (post-filename)
  "Extract the `#+tags:` from entry POST-FILENAME."
  (with-temp-buffer
    (insert-file-contents post-filename)
    (goto-char (point-min))
    (if (search-forward-regexp "^\\#\\+tags:[ ]*\\(.+\\)$" nil t)
        (split-string (match-string 1))
      nil)))

(defun org-static-blog-get-tag-tree ()
  "Return an association list of tags to filenames."
  (let ((tag-tree '()))
    (dolist (post-filename (org-static-blog-get-post-filenames))
      (let ((tags (org-static-blog-get-tags post-filename)))
        (dolist (tag tags)
          (if (assoc-string tag tag-tree t)
              (push post-filename (cdr (assoc-string tag tag-tree t)))
            (push (cons tag (list post-filename)) tag-tree)))))
    tag-tree))

(defun org-static-blog-get-body (post-filename &optional exclude-title)
  "Get the rendered HTML body without headers from POST-FILENAME."
  (with-temp-buffer
    (insert-file-contents (org-static-blog-matching-publish-filename post-filename))
    (buffer-substring-no-properties
     (progn
       (goto-char (point-min))
       (if exclude-title
           (progn (search-forward "<h1 class=\"post-title\">")
                  (search-forward "</h1>"))
         (search-forward "<div id=\"content\">"))
       (point))
     (progn
       (goto-char (point-max))
       (search-backward "<div id=\"postamble\" class=\"status\">")
       (search-backward "</div>")
       (point)))))

(defun org-static-blog-get-url (post-filename)
  "Generate a URL to entry POST-FILENAME."
  (concat org-static-blog-publish-url
          (file-name-nondirectory
           (org-static-blog-matching-publish-filename post-filename))))

;;;###autoload
(defun org-static-blog-publish-file (post-filename)
  "Publish a single entry POST-FILENAME.
The index page, archive page, and RSS feed are not updated."
  (interactive "f")
  (org-static-blog-with-find-file
   (org-static-blog-matching-publish-filename post-filename)
   (erase-buffer)
   (insert
    (concat "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"
\"https://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"https://www.w3.org/1999/xhtml\" lang=\"en\" xml:lang=\"en\">
<head>
<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\" />
<link rel=\"alternate\"
      type=\"appliation/rss+xml\"
      href=\"" org-static-blog-publish-url org-static-blog-rss-file "\"
      title=\"RSS feed for " org-static-blog-publish-url "\">
<title>" (org-static-blog-get-title post-filename) "</title>"
org-static-blog-page-header
"</head>
<body>
<div id=\"preamble\" class=\"status\">"
org-static-blog-page-preamble
"</div>
<div id=\"content\">"
(org-static-blog-entry-preamble post-filename)
(org-static-blog-render-entry-content post-filename)
(org-static-blog-entry-postamble post-filename)
"</div>
<div id=\"postamble\" class=\"status\">"
org-static-blog-page-postamble
"</div>
</body>
</html>"))))

(defun org-static-blog-render-entry-content (post-filename)
  "Render blog content as bare HTML without header."
  (org-static-blog-with-find-file
   post-filename
   (org-export-as 'org-static-blog-post-bare nil nil nil nil)))

(org-export-define-derived-backend 'org-static-blog-post-bare 'html
  :translate-alist '((template . (lambda (contents info) contents))))

(defun org-static-blog-assemble-index ()
  "Assemble the blog index page.
The index page contains the last `org-static-blog-index-length`
entries as full text entries."
  (let ((post-filenames (org-static-blog-get-post-filenames)))
    ;; reverse-sort, so that the later `last` will grab the newest entries
    (setq post-filenames (sort post-filenames (lambda (x y) (time-less-p (org-static-blog-get-date x)
                                                                         (org-static-blog-get-date y)))))
    (org-static-blog-assemble-multipost-page
     (concat org-static-blog-publish-directory org-static-blog-index-file)
     (last post-filenames org-static-blog-index-length))))

(defun org-static-blog-assemble-multipost-page (pub-filename post-filenames &optional front-matter)
  "Assemble a page that contains multiple posts one after another.
Posts are sorted in descending time."
  (org-static-blog-with-find-file
   pub-filename
   (erase-buffer)
   (insert
    (concat "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"
\"https://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"https://www.w3.org/1999/xhtml\" lang=\"en\" xml:lang=\"en\">
<head>
<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\" />
<link rel=\"alternate\"
      type=\"appliation/rss+xml\"
      href=\"" org-static-blog-publish-url org-static-blog-rss-file "\"
      title=\"RSS feed for " org-static-blog-publish-url "\">
<title>" org-static-blog-publish-title "</title>"
org-static-blog-page-header
"</head>
<body>
<div id=\"preamble\" class=\"status\">"
org-static-blog-page-preamble
"</div>
<div id=\"content\">"))
   (if front-matter
       (insert front-matter))
   (setq post-filenames (sort post-filenames (lambda (x y) (time-less-p (org-static-blog-get-date y)
                                                                        (org-static-blog-get-date x)))))
   (dolist (post-filename post-filenames)
     (insert (org-static-blog-get-body post-filename)))
   (insert
"<div id=\"archive\">
  <a href=\"" org-static-blog-publish-url org-static-blog-archive-file "\">Other posts</a>
</div>
</div>
</body>")))

(defun org-static-blog-entry-preamble (post-filename)
  (concat
   "<div class=\"post-date\">" (format-time-string "%d %b %Y" (org-static-blog-get-date post-filename)) "</div>"
   "<h1 class=\"post-title\">"
   "<a href=\"" (org-static-blog-get-url post-filename) "\">" (org-static-blog-get-title post-filename) "</a>"
   "</h1>\n"))

(defun org-static-blog-entry-postamble (post-filename)
  (let ((taglist-content ""))
    (when (and (org-static-blog-get-tags post-filename) org-static-blog-enable-tags)
      (setq taglist-content (concat "<div id=\"taglist\">"
                                    "<p><a href=\""
                                    org-static-blog-publish-url
                                    org-static-blog-tags-file
                                    "\">Tags:</a> "))
      (dolist (tag (org-static-blog-get-tags post-filename))
        (setq taglist-content (concat taglist-content "<a href=\""
                                      org-static-blog-publish-url
                                      "tags/" (downcase tag) ".html"
                                      "\">" tag "</a> ")))
      (setq taglist-content (concat taglist-content "</div>")))
    taglist-content))

(defun org-static-blog-assemble-rss ()
  "Assemble the blog RSS feed.
The RSS-feed is an XML file that contains every blog entry in a
machine-readable format."
  (let ((rss-filename (concat org-static-blog-publish-directory org-static-blog-rss-file))
        (rss-entries nil))
    (dolist (post-filename (org-static-blog-get-post-filenames))
      (let ((rss-date (org-static-blog-get-date post-filename))
            (rss-text (org-static-blog-get-rss-entry post-filename)))
        (add-to-list 'rss-entries (cons rss-date rss-text))))
    (org-static-blog-with-find-file
     rss-filename
     (erase-buffer)
     (insert "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<rss version=\"2.0\">
<channel>
  <title>" org-static-blog-publish-title "</title>
  <description>" org-static-blog-publish-title "</description>
  <link>" org-static-blog-publish-url "</link>
  <lastBuildDate>" (format-time-string "%a, %d %b %Y %H:%M:%S %z" (current-time)) "</lastBuildDate>\n")
     (dolist (entry (sort rss-entries (lambda (x y) (time-less-p (car y) (car x)))))
       (insert (cdr entry)))
     (insert "</channel>
</rss>"))))

(defun org-static-blog-get-rss-entry (post-filename)
  "Assemble RSS entry from post-filename.
The HTML content is taken from the rendered HTML post."
  (concat
   "<item>
  <title>" (org-static-blog-get-title post-filename) "</title>
  <description><![CDATA["
  (org-static-blog-get-body post-filename t) ; exclude headline!
  "]]></description>
  <link>"
  (concat org-static-blog-publish-url
          (file-name-nondirectory
           (org-static-blog-matching-publish-filename
            post-filename)))
  "</link>
  <pubDate>"
  (format-time-string "%a, %d %b %Y %H:%M:%S %z" (org-static-blog-get-date post-filename))
  "</pubDate>
</item>\n"))

(defun org-static-blog-assemble-archive ()
  "Re-render the blog archive page.
The archive page contains single-line links and dates for every
blog entry, but no entry body."
  (let ((archive-filename (concat org-static-blog-publish-directory org-static-blog-archive-file))
        (archive-entries nil))
    (dolist (post-filename (org-static-blog-get-post-filenames))
      (let ((date (org-static-blog-get-date post-filename))
            (title (org-static-blog-get-title post-filename))
            (url (org-static-blog-get-url post-filename)))
        (add-to-list 'archive-entries (list date title url))))
    (org-static-blog-with-find-file
     archive-filename
     (erase-buffer)
     (insert (concat
              "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"
\"https://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"https://www.w3.org/1999/xhtml\" lang=\"en\" xml:lang=\"en\">
<head>
<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\" />
<link rel=\"alternate\"
      type=\"appliation/rss+xml\"
      href=\"" org-static-blog-publish-url org-static-blog-rss-file "\"
      title=\"RSS feed for " org-static-blog-publish-url "\">
<title>" org-static-blog-publish-title "</title>"
org-static-blog-page-header
"</head>
<body>
<div id=\"preamble\" class=\"status\">"
org-static-blog-page-preamble
"</div>
<div id=\"content\">
<h1 class=\"title\">Archive</h1>\n"))
       (dolist (entry (sort archive-entries (lambda (x y) (time-less-p (car y) (car x)))))
         (insert
          (concat
           "<div class=\"post-date\">" (format-time-string "%d %b %Y" (nth 0 entry)) "</div>"
           "<h2 class=\"post-title\">"
           "<a href=\"" (nth 2 entry) "\">" (nth 1 entry) "</a>"
           "</h2>\n")))
       (insert "</body>\n </html>"))))

(defun org-static-blog-assemble-tags ()
  "Render the tag pages.
Each tag page contains the full text of all posts of a tag."
  (org-static-blog-assemble-tags-archive)
  (if (not (file-exists-p (concat org-static-blog-publish-directory "tags/")))
      (make-directory (concat org-static-blog-publish-directory "tags/")))
  (dolist (tag (org-static-blog-get-tag-tree))
    (org-static-blog-assemble-multipost-page
     (concat org-static-blog-publish-directory "tags/" (downcase (car tag)) ".html")
     (cdr tag)
     (concat "<h1 class=\"title\">Posts tagged \"" (car tag) "\":</h1>"))))

(defun org-static-blog-assemble-tags-archive ()
  "Assemble the blog tag archive page.
The archive page contains single-line links and dates for every
blog entry, sorted by tags, but no entry body."
  (let ((tags-archive-filename (concat org-static-blog-publish-directory org-static-blog-tags-file))
        (tag-tree (org-static-blog-get-tag-tree)))
    (org-static-blog-with-find-file
     tags-archive-filename
     (erase-buffer)
     (insert (concat
              "<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\"
\"https://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">
<html xmlns=\"https://www.w3.org/1999/xhtml\" lang=\"en\" xml:lang=\"en\">
<head>
<meta http-equiv=\"Content-Type\" content=\"text/html;charset=utf-8\" />
<link rel=\"alternate\"
      type=\"appliation/rss+xml\"
      href=\"" org-static-blog-publish-url org-static-blog-rss-file "\"
      title=\"RSS feed for " org-static-blog-publish-url "\">
<title>" org-static-blog-publish-title "</title>"
org-static-blog-page-header
"</head>
<body>
<div id=\"preamble\" class=\"status\">"
org-static-blog-page-preamble
"</div>
<div id=\"content\">"
"<h1 class=\"title\">Tags</h1>\n"))
     (dolist (tag tag-tree)
       (insert (concat "<h1 class=\"tags-title\">Posts tagged \"" (downcase (car tag)) "\":</h1>\n"))
       (dolist (post-filename (sort (cdr tag) (lambda (x y) (time-less-p (org-static-blog-get-date y)
                                                                         (org-static-blog-get-date x)))))
         (insert
          (concat
           "<div class=\"post-date\">"
           (format-time-string "%d %b %Y" (org-static-blog-get-date post-filename))
           "</div>"
           "<h2 class=\"post-title\">"
           "<a href=\"" (org-static-blog-get-url post-filename) "\">" (org-static-blog-get-title post-filename) "</a>"
           "</h2>\n"))))
     (insert "</body>\n </html>"))))


(provide 'org-static-blog)

;;; org-static-blog.el ends here
