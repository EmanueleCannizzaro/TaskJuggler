#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = RichTextScanner.rb -- The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008, 2009, 2010 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'UTF8String'
require 'TextScanner'

class TaskJuggler

  # The RichTextScanner is used by the RichTextParser to chop the input text
  # into digestable tokens. It specializes the TextScanner class for RichText
  # syntax. The scanner can operate in various modes. The current mode is
  # context dependent. The following modes are supported:
  #
  # :bop :     at the begining of a paragraph.
  # :bol :     at the begining of a line.
  # :inline :  in the middle of a line
  # :nowiki :  ignoring all MediaWiki special tokens
  # :ref :     inside of a REF [[ .. ]]
  # :href :    inside of an HREF [ .. ]
  # :func :    inside of a block <[ .. ]> or inline <- .. -> function
  class RichTextScanner < TextScanner

    def initialize(masterFile, messageHandler)
      tokenPatterns = [
        [ 'LINEBREAK', /\s*\n/, :bol, method('linebreak') ],
        [ nil, /\s*\n/, :bop, method('linebreak') ],
        [ 'SPACE', /[ \t\n]+/, :inline, method('space') ],
        # The <nowiki> token puts the scanner into :nowiki mode.
        [ nil, /<nowiki>/, [ :bop, :bol, :inline ], method('nowikiStart') ],
        [ nil, /<\/nowiki>/, :nowiki, method('nowikiEnd') ],
        [ 'WORD', /(<(?!\/nowiki>)|[^ \t\n<])+/, :nowiki ],
        [ 'SPACE', /[ \t]+/, :nowiki ],
        [ 'LINEBREAK', /\s*\n/, :nowiki ],
        [ 'BOLDITALIC', /'{5}/, [ :bop, :bol, :inline ], method('inlineMode') ],
        [ 'CODE', /''''/, [ :bop, :bol, :inline ], method('inlineMode') ],
        [ 'BOLD', /'''/, [ :bop, :bol, :inline ], method('inlineMode') ],
        [ 'ITALIC', /''/, [ :bop, :bol, :inline ], method('inlineMode') ],
        [ 'PRE', / [^\n]+\n?/, :bop, method('pre') ],
        # REF
        [ 'REF', /\[\[/, [ :bop, :bol, :inline ], method('refStart') ],
        [ 'REFEND', /\]\]/, :ref, method('refEnd') ],
        [ 'WORD', /(<(?!-)|(\](?!\])|[^|<\]]))+/, :ref, method('refWord') ],
        [ 'QUERY', /<-\w+->/, :ref, method('query') ],
        [ 'LITERAL', /\|/, :ref ],
        # HREF
        [ 'HREF', /\[/, [ :bop, :bol, :inline], method('hrefStart') ],
        [ 'HREFEND', /\]/, :href, method('hrefEnd') ],
        [ 'WORD', /(<(?!-)|[^ \t\]<])+/, :href ],
        [ 'QUERY', /<-\w+->/, :href, method('query') ],
        [ 'SPACE', /[ \t]+/, :href ],
        [ 'HLINE', /----/, [ :bop, :bol ], method('inlineMode') ],
        [ 'INLINEFUNCSTART', /<-/, [ :bop, :bol, :inline ],
          method('functionStart') ],
        [ 'INLINEFUNCEND', /->/ , :func, method('functionEnd') ],
        [ 'BLOCKFUNCSTART', /<\[/, [ :bop, :bol ], method('functionStart') ],
        [ 'BLOCKFUNCEND', /\]>/, :func, method('functionEnd') ],
        [ 'ID', /[a-zA-Z_]\w*/, :func ],
        [ 'STRING', /"(\\"|[^"])*?"/, :func, method('chop2') ],
        [ 'STRING', /'(\\'|[^'])*'/, :func, method('chop2') ],
        [ nil, /[ \t\n]+/, :func ],
        [ 'LITERAL', /./, :func ],
        [ 'TITLE*', /={2,5}/, [ :bop, :bol ], method('titleStart') ],
        [ 'TITLE*END', /={2,5}/, :inline, method('titleEnd') ],
        [ 'BULLET*', /\*{1,4} /, [ :bop, :bol ], method('bullet') ],
        [ 'NUMBER*', /\#{1,4} /, [ :bop, :bol ], method('number') ],
        [ nil, /\s+/, :bol, method('inlineMode') ],
        [ 'WORD', /[^ \n\t][^ \n\t\[<']*/, [ :bop, :bol, :inline ],
          method('inlineMode') ]
      ]
      super(masterFile, messageHandler, tokenPatterns, :bop)
      # Buffer to collect :ref WORD tokens that span multiple lines.
      @word = ''
    end

    private

    def space(type, match)
      if match.index("\n")
        # If the match contains a linebreak we switch to :bol mode.
        self.mode = :bol
        # And return an empty string.
        match = ''
      end
      [type, match ]
    end

    def linebreak(type, match)
      self.mode = :bop
      [ type, match ]
    end

    def inlineMode(type, match)
      self.mode = :inline
      [ type, match ]
    end

    def titleStart(type, match)
      self.mode = :inline
      [ "TITLE#{match.length - 1}", match ]
    end

    def titleEnd(type, match)
      [ "TITLE#{match.length - 1}END", match ]
    end

    def bullet(type, match)
      self.mode = :inline
      [ "BULLET#{match.length - 1}", match ]
    end

    def number(type, match)
      self.mode = :inline
      [ "NUMBER#{match.length - 1}", match ]
    end

    def nowikiStart(type, match)
      self.mode = :nowiki
      [ type, match ]
    end

    def nowikiEnd(type, match)
      self.mode = :inline
      [ type, match ]
    end

    def functionStart(type, match)
      @funcLastMode = @scannerMode
      self.mode = :func
      [ type, match ]
    end

    def functionEnd(type, match)
      self.mode = @funcLastMode
      @funcLastMode = nil
      [ type, match ]
    end

    def pre(type, match)
      [ type, match[1..-1] ]
    end

    def chop2(type, match)
      # Remove first and last character.
      [ type, match[1..-2] ]
    end

    def query(type, match)
      # Remove <- and ->.
      [ type, match[2..-3] ]
    end

    def hrefStart(type, match)
      @hrefLastMode = @scannerMode
      self.mode = :href
      [ type, match ]
    end

    def hrefEnd(type, match)
      self.mode = @hrefLastMode
      @hrefLastMode = nil
      [ type, match ]
    end

    def refStart(type, match)
      self.mode = :ref
      [ type, match ]
    end

    def refEnd(type, match)
      self.mode = :inline
      [ type, match ]
    end

    def refWord(type, match)
      @word += match
      if match[-1] == ?\n
        return [ nil, '' ]
      else
        w = @word
        @word = ''
        return [ type, w ]
      end
    end

  end

end
