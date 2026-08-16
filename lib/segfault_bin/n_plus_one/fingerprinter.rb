# frozen_string_literal: true

module SegfaultBin
  module NPlusOne
    module Fingerprinter
      BLOCK_COMMENT = %r{/\*.*?\*/}m
      LINE_COMMENT = /--[^\n]*/
      STRING_SQ = /'(?:[^'\\]|\\.)*'/
      # Postgres quotes *identifiers* with double quotes and MySQL with
      # backticks, so `"users"."id"` is a table and a column and not a string
      # literal. Scrubbing them the way string literals are scrubbed turned
      # every fingerprint into `select ?.* from ? where ?.? = ?` — the same
      # eleven characters for every primary-key lookup in the app, useless to
      # read and barely distinguishing to group by. The quotes come off and the
      # name stays.
      QUOTED_IDENT = /"((?:[^"]|"")*)"|`((?:[^`]|``)*)`/
      # Bind placeholders, before NUMERIC gets to the digits and leaves `$?`.
      BIND = /\$\d+/
      IN_LIST = /\bIN\s*\([^()]*\)/i
      NUMERIC = /\b\d+(?:\.\d+)?\b/
      WHITESPACE = /\s+/

      module_function

      def fingerprint(sql)
        s = sql.to_s.dup
        s.gsub!(BLOCK_COMMENT, " ")
        s.gsub!(LINE_COMMENT, " ")
        # Single quotes first: a string literal may contain a stray double
        # quote or backtick that would otherwise open a bogus identifier.
        s.gsub!(STRING_SQ, "?")
        s.gsub!(QUOTED_IDENT) { unquote(Regexp.last_match(1) || Regexp.last_match(2)) }
        s.gsub!(BIND, "?")
        s.gsub!(IN_LIST, "IN (?)")
        s.gsub!(NUMERIC, "?")
        s.gsub!(WHITESPACE, " ")
        s.strip!
        s.downcase!
        s
      end

      # An embedded quote is doubled inside a quoted identifier; undoubling it
      # keeps `"weird""name"` from turning into two tokens.
      def unquote(name)
        name.to_s.gsub('""', '"').gsub("``", "`")
      end
    end
  end
end
