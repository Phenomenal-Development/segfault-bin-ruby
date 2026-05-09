# frozen_string_literal: true

module SegfaultBin
  module NPlusOne
    module Fingerprinter
      BLOCK_COMMENT = %r{/\*.*?\*/}m
      LINE_COMMENT = /--[^\n]*/
      STRING_SQ = /'(?:[^'\\]|\\.)*'/
      STRING_DQ = /"(?:[^"\\]|\\.)*"/
      IN_LIST = /\bIN\s*\([^()]*\)/i
      NUMERIC = /\b\d+(?:\.\d+)?\b/
      WHITESPACE = /\s+/

      module_function

      def fingerprint(sql)
        s = sql.to_s.dup
        s.gsub!(BLOCK_COMMENT, " ")
        s.gsub!(LINE_COMMENT, " ")
        s.gsub!(STRING_SQ, "?")
        s.gsub!(STRING_DQ, "?")
        s.gsub!(IN_LIST, "IN (?)")
        s.gsub!(NUMERIC, "?")
        s.gsub!(WHITESPACE, " ")
        s.strip!
        s.downcase!
        s
      end
    end
  end
end
