-- =============================================================== --
-- SQL script to create all the tables and indices in the database --
-- =============================================================== --

-- The wclass table stores word classes, which includes parts of speech
-- and noun classes
--
CREATE TABLE wclass (
  cid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  ctx   TEXT UNIQUE NOT NULL,     -- Abbreviated textual code
  cis   TEXT NOT NULL,            -- Icelandic description
  cen   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_wclass_ctx
  ON wclass(ctx);

-- The dom table stores semantic domains
--
CREATE TABLE dom (
  did   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  dtx   TEXT UNIQUE NOT NULL,     -- Abbreviated textual code
  dlv   INTEGER NOT NULL,         -- 0: common, 1: specialized, 2: name
  dis   TEXT NOT NULL,            -- Icelandic description
  den   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_dom_dtx
  ON dom(dtx);

-- The grade table stores correctness grades
--
CREATE TABLE grade (
  gid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  giv   INTEGER UNIQUE NOT NULL,  -- DIM grade code 0-5
  gis   TEXT NOT NULL,            -- Icelandic description
  gen   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_grade_giv
  ON grade(giv);

-- The reg table stores language registers
--
CREATE TABLE reg (
  rid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  rtx   TEXT UNIQUE NOT NULL,     -- Abbreviated textual code
  ris   TEXT NOT NULL,            -- Icelandic description
  ren   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_reg_rtx
  ON reg(rtx);

-- The gflag table stores grammatical feature flags
--
CREATE TABLE gflag (
  fid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  ftx   TEXT UNIQUE NOT NULL,     -- Abbreviated textual code
  fis   TEXT NOT NULL,            -- Icelandic description
  fen   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_gflag_ftx
  ON gflag(ftx);

-- The word table stores headwords and word information
--
CREATE TABLE word (
  wid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wbid  INTEGER UNIQUE NOT NULL,  -- DMII word ID (BIN.ID)
  wlem  TEXT NOT NULL,            -- Headword/lemma
  cid   INTEGER NOT NULL          -- [ -> wclass table ]
          REFERENCES wclass(cid),
  wcp   INTEGER NOT NULL,         -- 1 if compound word, 0 otherwise
  gid   INTEGER NOT NULL          -- [ -> grade table ]
          REFERENCES grade(gid),
  wvs   INTEGER NOT NULL,         -- 0: core, 1: extended, 2: correction
  wsy   INTEGER NOT NULL          -- Stem syllable count, 0 if unknown
);

CREATE UNIQUE INDEX ix_word_wbid
  ON word(wbid);

CREATE INDEX ix_word_wlem
  ON word(wlem);

-- The wdom table associates sets of semantic domains with words
--
CREATE TABLE wdom (
  hid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wid   INTEGER NOT NULL          -- [ -> word table ]
          REFERENCES word(wid),
  did   INTEGER NOT NULL          -- [ -> dom table ]
          REFERENCES dom(did),
  UNIQUE (wid, did)
);

CREATE UNIQUE INDEX ix_wdom_rec
  ON wdom(wid, did);

-- The wreg table associates sets of language registers with words
--
CREATE TABLE wreg (
  xid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wid   INTEGER NOT NULL          -- [ -> word table ]
          REFERENCES word(wid),
  rid   INTEGER NOT NULL          -- [ -> reg table ]
          REFERENCES reg(rid),
  UNIQUE (wid, rid)
);

CREATE UNIQUE INDEX ix_wreg_rec
  ON wreg(wid, rid);

-- The wflag table associates sets of grammatical feature flags with
-- words
--
CREATE TABLE wflag (
  yid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wid   INTEGER NOT NULL          -- [ -> word table ]
          REFERENCES word(wid),
  fid   INTEGER NOT NULL          -- [ -> gflag table ]
          REFERENCES gflag(fid),
  UNIQUE (wid, fid)
);

CREATE UNIQUE INDEX ix_wflag_rec
  ON wflag(wid, fid);

-- The itag table stores inflectional tags
--
CREATE TABLE itag (
  mid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  cid   INTEGER NOT NULL          -- [ -> wclass table ]
          REFERENCES wclass(cid),
  mtx   TEXT NOT NULL,            -- Abbreviated textual code
  mis   TEXT NOT NULL,            -- Icelandic description
  men   TEXT NOT NULL,            -- English description
  UNIQUE (cid, mtx)
);

CREATE UNIQUE INDEX ix_itag_rec
  ON itag(cid, mtx);

-- The ival table stores inflectional values
--
CREATE TABLE ival (
  jid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  jtx   TEXT UNIQUE NOT NULL,     -- Abbreviated textual code
  jis   TEXT NOT NULL,            -- Icelandic description
  jen   TEXT NOT NULL             -- English description
);

CREATE UNIQUE INDEX ix_ival_jtx
  ON ival(jtx);

-- The infl table stores individual inflected forms
--
CREATE TABLE infl (
  iid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wid   INTEGER NOT NULL          -- [ -> word table ]
          REFERENCES word(wid),
  iform TEXT NOT NULL,            -- Inflectional form
  mid   INTEGER NOT NULL          -- [ -> itag table ]
          REFERENCES itag(mid),
  gid   INTEGER NOT NULL          -- [ -> grade table ]
          REFERENCES grade(gid)
);

CREATE INDEX ix_infl_wid
  ON infl(wid);

-- The ireg table associates sets of language registers with
-- inflectional forms
--
CREATE TABLE ireg (
  qid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  iid   INTEGER NOT NULL          -- [ -> infl table ]
          REFERENCES infl(iid),
  rid   INTEGER NOT NULL          -- [ -> reg table ]
          REFERENCES reg(rid),
  UNIQUE (iid, rid)
);

CREATE UNIQUE INDEX ix_ireg_rec
  ON ireg(iid, rid);

-- The iflag table associates sets of inflectional values with
-- inflectional forms
--
CREATE TABLE iflag (
  nid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  iid   INTEGER NOT NULL          -- [ -> infl table ]
          REFERENCES infl(iid),
  jid   INTEGER NOT NULL          -- [ -> ival table ]
          REFERENCES ival(jid),
  UNIQUE (iid, jid)
);

CREATE UNIQUE INDEX ix_iflag_rec
  ON iflag(iid, jid);
