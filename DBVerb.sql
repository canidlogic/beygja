-- ===================================================== --
-- SQL script to create verb-specific tables and indices --
-- ===================================================== --

-- The infl table stores individual inflected verb forms
--
CREATE TABLE infl (
  iid   INTEGER PRIMARY KEY ASC,  -- Built-in primary key
  wid   INTEGER NOT NULL          -- [ -> word table ]
          REFERENCES word(wid),
  icode TEXT NOT NULL,            -- Verb inflection code
  iord  INTEGER NOT NULL,         -- Inflection order
  iform TEXT NOT NULL,            -- Inflectional form
  gid   INTEGER NOT NULL          -- [ -> grade table ]
          REFERENCES grade(gid),
  UNIQUE (wid, icode, iord)
);

CREATE UNIQUE INDEX ix_infl_rec
  ON infl(wid, icode, iord);

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
