#!/usr/bin/env python3
"""Minimal, dependency-free Markdown -> HTML for the macOS installer's
license/welcome panes. The HTML is turned into RTF by `textutil`, so the
Installer shows a rendered document instead of raw Markdown syntax.

Supported subset (what our EULA/LICENSE/Welcome files use):
  #/##/### headings, **bold**, *italic*, `code`, > blockquote,
  - / * bullet lists, [text](url) links (rendered as text), --- rule, paragraphs.
Usage:  md_to_html.py <input.md>   # writes HTML to stdout
"""
import sys
import re
import html


def inline(text: str) -> str:
    text = html.escape(text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)      # links -> visible text
    text = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", text)      # **bold**
    text = re.sub(r"__([^_]+)__", r"<b>\1</b>", text)          # __bold__
    text = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", text)  # *italic*
    text = re.sub(r"`([^`]+)`", r"\1", text)                  # `code` -> plain
    return text


def convert(md: str) -> str:
    out, para, quote, bullets = [], [], [], []

    def flush_para():
        if para:  # join raw lines first, THEN format (so **bold** may span lines)
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para.clear()

    def flush_quote():
        if quote:
            out.append("<blockquote>" + inline(" ".join(quote)) + "</blockquote>")
            quote.clear()

    def flush_bullets():
        if bullets:
            out.append("<ul>" + "".join(f"<li>{inline(b)}</li>" for b in bullets) + "</ul>")
            bullets.clear()

    def flush_all():
        flush_para(); flush_quote(); flush_bullets()

    for raw in md.split("\n"):
        line = raw.rstrip()
        if not line.strip():
            flush_all()
            continue
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            flush_all()
            lvl = len(m.group(1))
            out.append(f"<h{lvl}>{inline(m.group(2))}</h{lvl}>")
            continue
        if re.match(r"^\s*[-*_]{3,}\s*$", line):
            flush_all(); out.append("<hr/>"); continue
        if line.lstrip().startswith(">"):
            flush_para(); flush_bullets()
            quote.append(re.sub(r"^\s*>\s?", "", line))
            continue
        mb = re.match(r"^\s*[-*]\s+(.*)$", line)
        if mb:
            flush_para(); flush_quote()
            bullets.append(mb.group(1))
            continue
        # plain text line: an indented continuation of a list item stays in that
        # item (so **bold** spanning wrapped lines closes correctly); otherwise it
        # is paragraph text. A blank line (handled above) is what ends a list.
        if bullets:
            bullets[-1] = bullets[-1] + " " + line.strip()
        else:
            flush_quote()
            para.append(line.strip())
    flush_all()

    style = (
        "body{font-family:-apple-system,'Helvetica Neue',Helvetica,Arial,sans-serif;"
        "font-size:12px;line-height:1.5;color:#1b1d29;margin:0;}"
        "h1{font-size:20px;font-weight:700;margin:0 0 12px;color:#12131c;}"
        "h2{font-size:15px;font-weight:700;margin:18px 0 6px;color:#12131c;}"
        "h3{font-size:13px;font-weight:700;margin:12px 0 4px;color:#12131c;}"
        "p{margin:0 0 9px;} b{font-weight:700;}"
        "blockquote{margin:10px 0;padding:8px 12px;border-left:3px solid #6E7BF2;"
        "background-color:#f2f3fb;color:#333;}"
        "ul{margin:0 0 9px 20px;} li{margin:3px 0;}"
        "hr{border:none;border-top:1px solid #d5d7e0;margin:14px 0;}"
    )
    return (
        "<html><head><meta charset=\"utf-8\"><style>" + style + "</style></head>"
        "<body>" + "\n".join(out) + "</body></html>"
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.stderr.write("usage: md_to_html.py <input.md>\n")
        sys.exit(2)
    with open(sys.argv[1], encoding="utf-8") as fh:
        sys.stdout.write(convert(fh.read()))
