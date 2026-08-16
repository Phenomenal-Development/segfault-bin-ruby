# frozen_string_literal: true

RSpec.describe SegfaultBin::NPlusOne::Fingerprinter do
  describe ".fingerprint" do
    it "replaces single-quoted string literals with ?" do
      sql = "SELECT * FROM users WHERE name = 'alice'"
      expect(described_class.fingerprint(sql)).to eq "select * from users where name = ?"
    end

    it "replaces numeric literals with ?" do
      sql = "SELECT * FROM users WHERE id = 42"
      expect(described_class.fingerprint(sql)).to eq "select * from users where id = ?"
    end

    it "collapses IN-lists so different list sizes share a fingerprint" do
      a = described_class.fingerprint("SELECT * FROM u WHERE id IN (1, 2, 3)")
      b = described_class.fingerprint("SELECT * FROM u WHERE id IN (4, 5, 6, 7)")
      expect(a).to eq b
      expect(a).to include("in (?)")
    end

    it "strips line comments" do
      sql = "SELECT 1 -- comment\nFROM x"
      expect(described_class.fingerprint(sql)).to eq "select ? from x"
    end

    it "strips block comments" do
      sql = "SELECT /* hint */ 1 FROM x"
      expect(described_class.fingerprint(sql)).to eq "select ? from x"
    end

    it "collapses whitespace" do
      sql = "SELECT  1\n  FROM   x"
      expect(described_class.fingerprint(sql)).to eq "select ? from x"
    end

    it "is case-insensitive" do
      a = described_class.fingerprint("SELECT * FROM Users WHERE id = 1")
      b = described_class.fingerprint("select * from users where id = 2")
      expect(a).to eq b
    end

    it "keeps double-quoted identifiers, unquoted" do
      sql = %(SELECT "posts"."id" FROM "posts" WHERE "user_id" = 1)
      expect(described_class.fingerprint(sql)).to eq "select posts.id from posts where user_id = ?"
    end

    it "keeps backtick-quoted identifiers" do
      sql = "SELECT `users`.* FROM `users` WHERE `users`.`id` = 42"
      expect(described_class.fingerprint(sql)).to eq "select users.* from users where users.id = ?"
    end

    it "collapses numbered bind placeholders to ? rather than $?" do
      sql = %(SELECT "users".* FROM "users" WHERE "users"."id" = $1 LIMIT $2)
      expect(described_class.fingerprint(sql)).to eq "select users.* from users where users.id = ? limit ?"
    end

    it "does not let a quote inside a string literal open an identifier" do
      sql = %(SELECT * FROM users WHERE name = 'a "b" c' AND id = 1)
      expect(described_class.fingerprint(sql)).to eq "select * from users where name = ? and id = ?"
    end

    it "undoubles an escaped quote inside an identifier" do
      sql = %(SELECT "we""ird" FROM t)
      expect(described_class.fingerprint(sql)).to eq %(select we"ird from t)
    end
  end
end
