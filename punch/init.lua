-- The punch core: one require for every module.
return {
  util = require("punch.util"),
  dates = require("punch.dates"),
  registry = require("punch.registry"),
  corpus = require("punch.corpus"),
  parser = require("punch.parser"),
  index = require("punch.index"),
  edit = require("punch.edit"),
}
