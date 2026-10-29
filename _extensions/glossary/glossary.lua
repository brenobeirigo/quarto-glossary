-- A Quarto glossary filter using Obsidian-style wiki links.
--
-- References:
--   [[entry-id]]
--   [[entry-id|custom display text]]
--
-- Glossary placeholder:
--   ::: {.glossary}
--   :::
--
-- Entries come from one or more YAML/JSON files (glossary.path), from the
-- document or project metadata (glossary.entries), or from both.

local VERSION = "0.5.0"

local registry = nil
local settings = nil
local used = {}
local seen = {}
local document_meta = nil
local glossary_citation_ids = {}
local document_has_glossary = false
local document_lists_all = false

local function fail(message)
  io.stderr:write("glossary: " .. tostring(message) .. "\n")
  os.exit(1)
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function meta_text(value, fallback)
  if value == nil then
    return fallback
  end
  local text = trim(pandoc.utils.stringify(value))
  if text == "" then
    return fallback
  end
  return text
end

local function meta_bool(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "boolean" then
    return value
  end
  local text = meta_text(value, ""):lower()
  if text == "true" or text == "yes" or text == "1" then
    return true
  end
  if text == "false" or text == "no" or text == "0" then
    return false
  end
  fail("expected a Boolean value, received " .. text)
end

local function path_exists(path)
  local handle = io.open(path, "r")
  if handle then
    handle:close()
    return true
  end
  return false
end

local function resolve_source_path(path)
  if pandoc.path.is_absolute(path) then
    return path
  end

  local candidates = pandoc.List({})
  if quarto.project and quarto.project.directory then
    candidates:insert(pandoc.path.join({quarto.project.directory, path}))
  end
  if quarto.doc and quarto.doc.input_file then
    candidates:insert(pandoc.path.join({
      pandoc.path.directory(quarto.doc.input_file), path
    }))
  end
  candidates:insert(path)

  for _, candidate in ipairs(candidates) do
    if path_exists(candidate) then
      return candidate
    end
  end
  return candidates[1] or path
end

local function read_file(path)
  local handle, message = io.open(path, "r")
  if not handle then
    fail("cannot read " .. path .. ": " .. tostring(message))
  end
  local raw = handle:read("*a")
  handle:close()
  return raw
end

local function decode_source(path)
  local raw = read_file(path)
  if path:lower():match("%.json$") then
    local decode = (quarto.json and quarto.json.decode) or
      (pandoc.json and pandoc.json.decode)
    if not decode then
      fail("requires Quarto or Pandoc JSON support to read " .. path)
    end
    return decode(raw)
  end

  -- Pandoc reads YAML metadata reliably when it is wrapped as a metadata
  -- block. This keeps the extension dependency-free.
  local wrapped = "---\n" .. raw .. "\n---\n"
  local parsed = pandoc.read(wrapped, "markdown")
  return parsed.meta
end

local function source_rows(source)
  if source.entries then
    return source.entries
  end
  if source.terms then
    return source.terms
  end
  if source.glossary and type(source.glossary) ~= "string" then
    return source.glossary
  end
  if source.groups then
    local rows = pandoc.List({})
    for _, group in ipairs(source.groups) do
      for _, row in ipairs(group.rows or {}) do
        rows:insert(row)
      end
    end
    return rows
  end
  fail("source must contain entries, terms, glossary, or groups[].rows")
end

local function row_value(row, names, fallback)
  for _, name in ipairs(names) do
    if row[name] ~= nil then
      return meta_text(row[name], fallback)
    end
  end
  return fallback
end

local function meta_markdown(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "string" then
    return trim(value)
  end
  local value_type = pandoc.utils.type(value)
  if value_type == "Inlines" or value_type == "MetaInlines" then
    return trim(pandoc.write(
      pandoc.Pandoc({pandoc.Plain(pandoc.Inlines(value))}), "markdown"))
  end
  if value_type == "Blocks" or value_type == "MetaBlocks" then
    return trim(pandoc.write(pandoc.Pandoc(pandoc.Blocks(value)), "markdown"))
  end
  return meta_text(value, fallback)
end

local function row_markdown(row, names, fallback)
  for _, name in ipairs(names) do
    if row[name] ~= nil then
      return meta_markdown(row[name], fallback)
    end
  end
  return fallback
end

-- YAML lists arrive as pandoc Lists and JSON arrays as plain Lua tables.
-- Inlines are also Lua sequences, so they must be excluded: a scalar such as
-- `see: a, b` is a string to split, not a list of words.
local function is_list_value(value)
  local value_type = pandoc.utils.type(value)
  return value_type == "List" or value_type == "MetaList" or
    value_type == "table"
end

local function text_list(value)
  local result = pandoc.List({})
  if is_list_value(value) then
    for _, item in ipairs(value) do
      local text = meta_text(item, "")
      if text ~= "" then
        result:insert(text)
      end
    end
    return result
  end
  local text = meta_text(value, "")
  for item in text:gmatch("[^,]+") do
    item = trim(item)
    if item ~= "" then
      result:insert(item)
    end
  end
  return result
end

local function row_list(row, names)
  for _, name in ipairs(names) do
    local value = row[name]
    if value ~= nil then
      return text_list(value)
    end
  end
  return pandoc.List({})
end

local function normalize_entry(row, source_path)
  local entry = {}
  entry.id = row_value(row, {"id", "key", "label"}, "")
  if entry.id == "" then
    fail("entry in " .. source_path .. " has no id")
  end
  if not entry.id:match("^[%w][%w_.:%-]*$") then
    fail("id '" .. entry.id ..
      "' must start with a letter or number and contain only letters, " ..
      "numbers, underscore, period, colon, or hyphen")
  end

  entry.kind = row_value(row, {"kind", "type"}, "term"):lower()
  if entry.kind ~= "term" and entry.kind ~= "acronym" then
    fail("entry '" .. entry.id .. "' has unsupported kind '" .. entry.kind ..
      "' (expected term or acronym)")
  end
  entry.term = row_value(row, {"term", "name"}, "")
  entry.short = row_value(row, {"short", "abbreviation", "acronym"}, "")
  entry.long = row_value(row, {"long", "expansion"}, "")
  entry.text = row_value(row, {"text"}, "")
  entry.plural = row_value(row, {"plural"}, "")
  entry.first = row_value(row, {"first"}, "")
  entry.first_plural = row_value(row, {"first-plural", "firstplural"}, "")
  entry.short_plural = row_value(row,
    {"short-plural", "shortplural"}, "")
  entry.long_plural = row_value(row,
    {"long-plural", "longplural"}, "")
  entry.symbol = row_markdown(row, {"symbol"}, "")
  entry.definition = row_markdown(row,
    {"description", "definition", "tooltip"}, "")
  entry.tooltip = row_value(row,
    {"tooltip", "description", "definition"}, "")
  entry.sort = row_value(row, {"sort"}, "")
  entry.see = row_list(row, {"see"})
  entry.see_also = row_list(row, {"see-also", "seealso"})

  -- Compatibility with the groups[].rows schema: acronym rows may use `term`
  -- for the short form and `definition` for the expansion.
  if entry.kind == "acronym" then
    if entry.short == "" then
      entry.short = entry.term
    end
    if entry.long == "" then
      entry.long = entry.definition
    end
    if entry.term == "" then
      entry.term = entry.short
    end
    if entry.definition == "" then
      entry.definition = entry.long
    end
    if entry.tooltip == "" then
      entry.tooltip = entry.long
    end
    if entry.short_plural == "" then
      entry.short_plural = entry.short .. "s"
    end
    if entry.long_plural == "" then
      entry.long_plural = entry.long .. "s"
    end
    if entry.text == "" then
      entry.text = entry.short
    end
    if entry.plural == "" then
      entry.plural = entry.short_plural
    end
    if entry.first == "" then
      entry.first = entry.long .. " (" .. entry.short .. ")"
    end
    if entry.first_plural == "" then
      entry.first_plural = entry.long_plural .. " (" .. entry.short_plural .. ")"
    end
  else
    if entry.term == "" then
      fail("entry '" .. entry.id .. "' has no term or name")
    end
    if entry.tooltip == "" then
      entry.tooltip = entry.definition
    end
    if entry.text == "" then
      entry.text = entry.term
    end
    if entry.plural == "" then
      entry.plural = entry.text .. "s"
    end
    if entry.first == "" then
      entry.first = entry.text
    end
    if entry.first_plural == "" then
      entry.first_plural = entry.plural
    end
  end

  if entry.definition == "" then
    fail("entry '" .. entry.id .. "' has no definition")
  end
  if entry.sort == "" then
    entry.sort = entry.short ~= "" and entry.short or entry.term
  end
  entry.source = source_path
  return entry
end

-- `path` accepts one file or a list of files. An empty string, an empty list,
-- or `false` loads no file, so a page can rely on inline entries alone.
-- Returns nil when the option is absent.
local function vocabulary_paths(value)
  if value == nil then
    return nil
  end
  if type(value) == "boolean" then
    if value then
      fail("path must be a file name, a list of file names, or false")
    end
    return pandoc.List({})
  end
  if is_list_value(value) then
    return text_list(value)
  end
  local paths = pandoc.List({})
  local text = meta_text(value, "")
  if text ~= "" then
    paths:insert(text)
  end
  return paths
end

local function inline_rows(config)
  local rows = config.entries
  if rows == nil then
    return pandoc.List({})
  end
  if not is_list_value(rows) then
    fail("glossary.entries must be a list of entries")
  end
  return rows
end

-- Front matter of files pulled in with {{< include >}}. Quarto merges it with
-- the enclosing document, so a second include can replace the first one's
-- glossary.entries; the filter reads every included file itself instead.
local included_metadata_patterns = {}

local function front_matter(raw)
  raw = raw:gsub("^\239\187\191", ""):gsub("\r\n", "\n")
  local yaml = raw:match("^%-%-%-[ \t]*\n(.-)\n%-%-%-[ \t]*\n")
  if not yaml then
    return {}, nil
  end
  return pandoc.read("---\n" .. yaml .. "\n---\n", "markdown").meta, yaml
end

local function block_signature(block)
  return block.t .. ":" ..
    trim(pandoc.utils.stringify(block):gsub("%s+", " "))
end

-- An include in the middle of a document, especially inside a fenced div, can
-- leave its front matter in the body as ordinary Markdown. Remember the blocks
-- that exact front matter parses to, so they can be removed again.
local function remember_metadata_pattern(yaml)
  for _, reader in ipairs({
      "markdown-yaml_metadata_block-simple_tables-multiline_tables-pipe_tables+smart",
      "markdown-yaml_metadata_block-simple_tables-multiline_tables-pipe_tables-smart",
      "markdown-yaml_metadata_block+smart",
      "markdown-yaml_metadata_block-smart"}) do
    local parsed = pandoc.read("---\n" .. yaml .. "\n---\n", reader)
    local pattern = {}
    for _, block in ipairs(parsed.blocks) do
      pattern[#pattern + 1] = block_signature(block)
    end
    if #pattern > 0 then
      included_metadata_patterns[#included_metadata_patterns + 1] = pattern
    end
  end
end

local function strip_included_metadata(blocks)
  if #included_metadata_patterns == 0 then
    return nil
  end
  local result, index, changed = pandoc.Blocks({}), 1, false
  while index <= #blocks do
    local length = 0
    for _, pattern in ipairs(included_metadata_patterns) do
      local matches = index + #pattern - 1 <= #blocks
      for offset = 1, matches and #pattern or 0 do
        if block_signature(blocks[index + offset - 1]) ~= pattern[offset] then
          matches = false
          break
        end
      end
      if matches then
        length = #pattern
        break
      end
    end
    if length > 0 then
      index = index + length
      changed = true
    else
      result:insert(blocks[index])
      index = index + 1
    end
  end
  return changed and result or nil
end

local function display_path(path)
  if quarto.project and quarto.project.directory then
    local relative = pandoc.path.make_relative(path, quarto.project.directory)
    if not relative:match("^%.%.") then
      return (relative:gsub("\\", "/"))
    end
  end
  return (path:gsub("\\", "/"))
end

-- Entry lists in the front matter of included files, nested includes first
-- found first. Commented-out includes are ignored.
local function included_entry_sources()
  local sources, visited = pandoc.List({}), {}
  local input = tostring(quarto.doc.input_file or "")
  if input == "" or not path_exists(input) then
    return sources
  end
  local function visit(path, included)
    path = pandoc.path.normalize(path)
    if visited[path] then
      return
    end
    visited[path] = true
    local raw = read_file(path)
    if included then
      local meta, yaml = front_matter(raw)
      if meta.glossary and meta.glossary.entries then
        sources:insert({rows = meta.glossary.entries, path = display_path(path)})
        remember_metadata_pattern(yaml)
      end
    end
    raw = raw:gsub("<!%-%-.-%-%->", "")
    for before, target in raw:gmatch("(.?){{<%s*include%s+([^>]-)%s*>}}") do
      -- `{{{< include >}}}` is Quarto's escaped, literal form.
      if before == "{" then
        goto continue
      end
      target = trim(target):gsub('^"(.-)"$', "%1"):gsub("^'(.-)'$", "%1")
      local candidates = {}
      if target:match("^/") and quarto.project and quarto.project.directory then
        candidates[1] = pandoc.path.join({quarto.project.directory, target:sub(2)})
      else
        candidates[1] = pandoc.path.join({pandoc.path.directory(path), target})
        candidates[2] = resolve_source_path(target)
      end
      for _, candidate in ipairs(candidates) do
        if path_exists(candidate) then
          visit(candidate, true)
          break
        end
      end
      ::continue::
    end
  end
  visit(input, false)
  return sources
end

local compared_fields = {
  "kind", "term", "short", "long", "text", "plural", "first", "first_plural",
  "short_plural", "long_plural", "symbol", "definition", "tooltip", "sort",
  "see", "see_also",
}

-- The first field in which two definitions of one id differ, or nil.
local function entry_difference(left, right)
  for _, field in ipairs(compared_fields) do
    local a, b = left[field], right[field]
    if type(a) == "table" then
      if #a ~= #b then
        return field
      end
      for index, item in ipairs(a) do
        if item ~= b[index] then
          return field
        end
      end
    elseif a ~= b then
      return field
    end
  end
  return nil
end

local function load_registry(meta)
  local config = meta.glossary or {}
  local rows = inline_rows(config)
  local included = included_entry_sources()
  local paths = vocabulary_paths(config.path)
  if paths == nil then
    paths = (#rows > 0 or #included > 0) and pandoc.List({}) or
      pandoc.List({"glossary.yml"})
  end

  settings = {
    strict = meta_bool(config.strict, true),
    include_unused = meta_bool(config["include-unused"], false),
    link = meta_bool(config.link, true),
    html_definition_display = meta_text(
      config["html-definition-display"], "balloon"):lower(),
    html_glossary_page = meta_text(config["html-glossary-page"], ""),
    load_latex_package = meta_bool(config["latex-load-package"], true),
    title = meta_text(config.title, "Glossary"),
    acronym_title = meta_text(config["acronym-title"], "Acronyms"),
    heading_level = tonumber(meta_text(config["heading-level"], "1")) or 1,
    latex_package = meta_text(config["latex-package"],
      "glossaries-extra"):lower(),
    latex_backend = meta_text(config["latex-backend"], "noidx"):lower(),
    latex_location_lists = meta_bool(config["latex-location-lists"], false),
    latex_sort = meta_text(config["latex-sort"], "word"):lower(),
    latex_style = meta_text(config["latex-style"], ""),
    acronym_style = meta_text(config["acronym-style"], "long-short-desc"),
    bib2gls_file = meta_text(config["bib2gls-file"], ""),
  }

  if settings.latex_backend == "bib2gls" then
    settings.latex_package = "glossaries-extra"
  end
  if settings.latex_package ~= "glossaries" and
      settings.latex_package ~= "glossaries-extra" then
    fail("latex-package must be glossaries or glossaries-extra")
  end
  if settings.latex_backend ~= "noidx" and
      settings.latex_backend ~= "makeindex" and
      settings.latex_backend ~= "bib2gls" then
    fail("latex-backend must be noidx, makeindex, or bib2gls")
  end
  if settings.html_definition_display ~= "balloon" and
      settings.html_definition_display ~= "tooltip" then
    fail("html-definition-display must be balloon or tooltip")
  end
  if settings.latex_sort ~= "word" and settings.latex_sort ~= "letter" and
      settings.latex_sort ~= "case" and settings.latex_sort ~= "def" and
      settings.latex_sort ~= "use" then
    fail("latex-sort must be word, letter, case, def, or use")
  end

  local result = {
    current = {},
    ordered = pandoc.List({}),
    has_acronyms = false,
    has_terms = false,
  }
  -- The same entry may arrive from several places: a fragment included twice,
  -- or front matter that Quarto merged into the document. Identical copies
  -- are one entry; a second, different meaning stops the render.
  local function add_entry(entry)
    local existing = result.current[entry.id]
    if existing then
      if existing.source == entry.source then
        fail("duplicate glossary id '" .. entry.id .. "' in " .. entry.source)
      end
      local field = entry_difference(existing, entry)
      if field == nil then
        return
      end
      fail("glossary id '" .. entry.id .. "' is defined differently in " ..
        existing.source .. " and " .. entry.source .. " (" ..
        field:gsub("_", "-") .. " differs). Give one of them another id, " ..
        "or make the two definitions identical")
    end
    result.current[entry.id] = entry
    result.ordered:insert(entry)
    if entry.kind == "acronym" then
      result.has_acronyms = true
    else
      result.has_terms = true
    end
  end

  local loaded = {}
  for _, path in ipairs(paths) do
    local resolved = resolve_source_path(path)
    if not loaded[resolved] then
      loaded[resolved] = true
      if not path_exists(resolved) then
        fail("cannot find vocabulary file '" .. path .. "'. Set glossary.path " ..
          "to a YAML or JSON file, or define glossary.entries in the " ..
          "document metadata")
      end
      for _, row in ipairs(source_rows(decode_source(resolved))) do
        add_entry(normalize_entry(row, path))
      end
    end
  end
  -- Included files come before the document's own entries, which may hold
  -- copies Quarto merged from them, so a conflict names the files involved.
  for _, source in ipairs(included) do
    for _, row in ipairs(source.rows) do
      add_entry(normalize_entry(row, source.path))
    end
  end
  for _, row in ipairs(rows) do
    add_entry(normalize_entry(row, "glossary.entries"))
  end

  for _, entry in ipairs(result.ordered) do
    for _, related in ipairs(entry.see) do
      if not result.current[related] then
        fail("entry '" .. entry.id .. "' refers to unknown see target '" ..
          related .. "'")
      end
    end
    for _, related in ipairs(entry.see_also) do
      if not result.current[related] then
        fail("entry '" .. entry.id ..
          "' refers to unknown see-also target '" .. related .. "'")
      end
    end
  end

  table.sort(result.ordered, function(left, right)
    return left.sort:lower() < right.sort:lower()
  end)
  return result
end

local function markdown_inlines(text)
  local parsed = pandoc.read(text, "markdown")
  if #parsed.blocks == 0 then
    return pandoc.Inlines({})
  end
  return pandoc.utils.blocks_to_inlines(parsed.blocks)
end

local function markdown_blocks(text)
  return pandoc.read(text, "markdown").blocks
end

-- Balloons, titles, and accessible labels are plain text. A parenthetical
-- citation would show up there as a raw [@key], so it is dropped; the
-- generated list keeps the complete definition and its citations.
local function plain_definition(text)
  local inlines = markdown_inlines(text):walk({
    Cite = function(cite)
      local first = cite.citations[1]
      if first and first.mode == "AuthorInText" then
        return nil
      end
      return {}
    end,
    Note = function()
      return {}
    end,
  })
  local plain = pandoc.utils.stringify(inlines)
    :gsub("%s+", " ")
    :gsub("%s+([%.,;:!?%)])", "%1")
  return trim(plain)
end

local function default_display(entry)
  if entry.kind == "acronym" and entry.short ~= "" then
    return entry.short
  end
  return entry.text
end

local reference_forms = {
  auto = true,
  text = true,
  first = true,
  plural = true,
  short = true,
  long = true,
  full = true,
  ["short-plural"] = true,
  ["long-plural"] = true,
  ["full-plural"] = true,
  symbol = true,
}

local function parse_reference_spec(display)
  if display == "" then
    return {form = "auto", capitalized = false}
  end
  if display:sub(1, 1) == "=" then
    return {custom = display:sub(2)}
  end
  if display == "capitalized" then
    return {form = "auto", capitalized = true}
  end
  local capitalized_form = display:match("^cap:(.+)$")
  if capitalized_form and reference_forms[capitalized_form] then
    return {form = capitalized_form, capitalized = true}
  end
  if reference_forms[display] then
    return {form = display, capitalized = false}
  end
  return {custom = display}
end

local function capitalize_inlines(inlines)
  local changed = false
  local function capitalize_inline(inline)
    if changed then
      return inline
    end
    if inline.t == "Str" then
      inline.text = inline.text:gsub("^%l", string.upper, 1)
      changed = true
    elseif inline.content then
      inline.content = inline.content:walk({Inline = capitalize_inline})
    end
    return inline
  end
  return inlines:walk({Inline = capitalize_inline})
end

local function display_for_form(entry, form, heading)
  if entry.kind ~= "acronym" then
    if form == "plural" or form == "short-plural" or
        form == "long-plural" or form == "full-plural" then
      return entry.plural
    end
    if form == "first" or form == "full" then
      return entry.first
    end
    if form == "symbol" then
      if entry.symbol == "" then
        fail("entry '" .. entry.id .. "' has no symbol")
      end
      return entry.symbol
    end
    return entry.text
  end

  if form == "symbol" then
    if entry.symbol == "" then
      fail("entry '" .. entry.id .. "' has no symbol")
    end
    return entry.symbol
  elseif form == "short" or form == "text" then
    return entry.short
  elseif form == "long" then
    return entry.long
  elseif form == "full" or form == "first" then
    return entry.first
  elseif form == "short-plural" then
    return entry.short_plural
  elseif form == "long-plural" then
    return entry.long_plural
  elseif form == "full-plural" then
    return entry.first_plural
  elseif form == "plural" then
    if heading or seen[entry.id] then
      return entry.short_plural
    end
    seen[entry.id] = true
    return entry.first_plural
  end

  if heading or seen[entry.id] then
    return entry.short
  end
  seen[entry.id] = true
  return entry.first
end

local function reference_content(entry, spec, heading)
  local content
  if spec.custom ~= nil then
    content = markdown_inlines(spec.custom)
  else
    content = markdown_inlines(display_for_form(entry, spec.form, heading))
  end
  if spec.capitalized then
    content = capitalize_inlines(content)
  end
  return content
end

local function markdown_inline_to_latex(text)
  local inlines = markdown_inlines(text)
  return trim(pandoc.write(pandoc.Pandoc({pandoc.Plain(inlines)}), "latex"))
end

-- Error messages name the document relative to the project or working
-- directory, which is shorter and keeps local paths out of CI logs.
local function input_label()
  local input = quarto.doc.input_file
  if not input then
    return "the input document"
  end
  local base = (quarto.project and quarto.project.directory) or
    pandoc.system.get_working_directory()
  if base and pandoc.path.is_absolute(input) then
    local relative = pandoc.path.make_relative(input, base)
    if not relative:match("^%.%.") then
      return (relative:gsub("\\", "/"))
    end
  end
  return input
end

local function lookup_entry(id)
  local entry = registry.current[id]
  if entry then
    return entry
  end
  if settings.strict then
    fail("unknown glossary key [[" .. id .. "]] in " .. input_label())
  end
  return nil
end

local function latex_escape(text)
  local replacements = {
    ["\\"] = "\\textbackslash{}",
    ["{"] = "\\{",
    ["}"] = "\\}",
    ["#"] = "\\#",
    ["$"] = "\\$",
    ["%"] = "\\%",
    ["&"] = "\\&",
    ["_"] = "\\_",
    ["^"] = "\\textasciicircum{}",
    ["~"] = "\\textasciitilde{}",
  }
  local output = {}
  for character in text:gmatch("[\0-\127\194-\244][\128-\191]*") do
    table.insert(output, replacements[character] or character)
  end
  return table.concat(output)
end

local function latex_reference(entry, display)
  used[entry.id] = true
  local spec = parse_reference_spec(display)
  if spec.custom == nil and spec.form == "auto" then
    local command = spec.capitalized and "\\Gls{" or "\\gls{"
    return pandoc.RawInline("latex", command .. entry.id .. "}")
  elseif spec.custom == nil and spec.form == "plural" then
    local command = spec.capitalized and "\\Glspl{" or "\\glspl{"
    return pandoc.RawInline("latex", command .. entry.id .. "}")
  end

  local content
  if spec.custom ~= nil then
    content = markdown_inline_to_latex(spec.custom)
  else
    local inlines = reference_content(entry, spec, false)
    content = trim(pandoc.write(
      pandoc.Pandoc({pandoc.Plain(inlines)}), "latex"))
  end
  return pandoc.RawInline("latex", "\\glsadd{" .. entry.id .. "}" ..
    "\\glslink{" .. entry.id .. "}{" .. content .. "}")
end

-- With html-glossary-page set, a reference on a page without its own glossary
-- list links to the entry on that page. The target keeps its .qmd extension so
-- Quarto rewrites it to the rendered page, including pages in subfolders.
local function html_glossary_target(entry)
  local fragment = "#glossary-" .. entry.id
  if document_has_glossary or settings.html_glossary_page == "" then
    return fragment
  end
  local target = resolve_source_path(settings.html_glossary_page)
  local input = tostring(quarto.doc.input_file or "document.qmd")
  if not pandoc.path.is_absolute(input) and quarto.project and quarto.project.directory then
    input = pandoc.path.join({quarto.project.directory, input})
  end
  local relative = pandoc.path.make_relative(target, pandoc.path.directory(input))
  return (relative:gsub("\\", "/")) .. fragment
end

-- A reference links only when its list entry exists: on this page, or on the
-- shared html-glossary-page. Otherwise the link would point at nothing (and
-- Typst refuses to compile a link to a missing label).
local function html_links_enabled()
  return settings.link and
    (document_has_glossary or settings.html_glossary_page ~= "")
end

local function html_reference(entry, display)
  used[entry.id] = true
  local spec = parse_reference_spec(display)
  local content = reference_content(entry, spec, false)
  local definition = plain_definition(entry.tooltip)
  local attributes = {
    {"tabindex", "0"},
    {"data-glossary-id", entry.id},
    {"aria-label", pandoc.utils.stringify(content) .. ": " .. definition},
  }
  local classes = {"glossary-term"}
  local link_title = ""
  local link = html_links_enabled()
  if settings.html_definition_display == "balloon" then
    classes[#classes + 1] = "glossary-balloon"
    attributes[#attributes + 1] = {"data-glossary-definition", definition}
  else
    link_title = definition
    if not link then
      attributes[#attributes + 1] = {"title", definition}
    end
  end
  if link then
    table.insert(classes, 1, "glossary-link")
    return pandoc.Link(content, html_glossary_target(entry), link_title,
      pandoc.Attr("", classes, attributes))
  end
  return pandoc.Span(content,
    pandoc.Attr("", classes, attributes))
end

local function other_reference(entry, display)
  used[entry.id] = true
  local content = reference_content(entry, parse_reference_spec(display), false)
  if not (settings.link and document_has_glossary) then
    return pandoc.Span(content, pandoc.Attr("", {"glossary-term"}))
  end
  return pandoc.Link(content, "#glossary-" .. entry.id,
    plain_definition(entry.tooltip),
    pandoc.Attr("", {"glossary-link"}))
end

local function glossary_reference(id, display, original)
  id = trim(id)
  display = trim(display)
  local entry = lookup_entry(id)
  if not entry then
    return pandoc.Str(original)
  end
  if quarto.doc.is_format("latex") or FORMAT:match("latex") then
    return latex_reference(entry, display)
  end
  if quarto.doc.is_format("html") or FORMAT:match("html") then
    return html_reference(entry, display)
  end
  return other_reference(entry, display)
end

local function heading_reference(id, display, original)
  id = trim(id)
  display = trim(display)
  local entry = lookup_entry(id)
  if not entry then
    return pandoc.Inlines({pandoc.Str(original)})
  end
  used[entry.id] = true
  return reference_content(entry, parse_reference_spec(display), true)
end

local function insert_replacement(output, replacement)
  if replacement.t then
    output:insert(replacement)
    return
  end
  for _, inline in ipairs(replacement) do
    output:insert(inline)
  end
end

local function expand_text(output, text, reference)
  local open_start, open_end = text:find("%[%[")
  if not open_start then
    output:insert(pandoc.Str(text))
    return
  end
  local close_start, close_end = text:find("%]%]", open_end + 1)
  if not close_start then
    output:insert(pandoc.Str(text))
    return
  end

  local before = text:sub(1, open_start - 1)
  if before ~= "" then
    output:insert(pandoc.Str(before))
  end

  local original = text:sub(open_start, close_end)
  local body = text:sub(open_end + 1, close_start - 1)
  local separator = body:find("|", 1, true)
  local id = separator and body:sub(1, separator - 1) or body
  local display = separator and body:sub(separator + 1) or ""
  insert_replacement(output, reference(id, display, original))

  local after = text:sub(close_end + 1)
  if after ~= "" then
    expand_text(output, after, reference)
  end
end

-- True when the text ends inside a reference: its last [[ has no ]] after it.
local function ends_inside_reference(text)
  local last_open = nil
  local position = 1
  while true do
    local start = text:find("[[", position, true)
    if not start then
      break
    end
    last_open = start
    position = start + 2
  end
  return last_open ~= nil and not text:find("]]", last_open + 2, true)
end

local function expand_inlines_with(inlines, reference)
  local output = pandoc.Inlines({})
  local index = 1
  while index <= #inlines do
    local item = inlines[index]
    if item.t == "Str" and item.text:find("[[", 1, true) then
      -- A reference with spaces, such as [[key|custom text]], spans several
      -- Str and Space inlines. Join them until no reference is left open.
      -- If one stays open, fall back to the first span that closes a
      -- reference and leave the unmatched [[ as literal text.
      local pieces = {item.text}
      local cursor = index
      local token = item.text
      local closed, first_close
      local function record()
        if not ends_inside_reference(token) then
          closed = {cursor = cursor, token = token}
        elseif not first_close and token:find("]]", 1, true) then
          first_close = {cursor = cursor, token = token}
        end
      end
      record()
      while not closed and cursor < #inlines do
        local following = inlines[cursor + 1]
        if following.t == "Space" or following.t == "SoftBreak" then
          table.insert(pieces, " ")
        elseif following.t == "Str" then
          table.insert(pieces, following.text)
        else
          break
        end
        cursor = cursor + 1
        token = table.concat(pieces)
        record()
      end
      local match = closed or first_close
      if match then
        expand_text(output, match.token, reference)
        index = match.cursor + 1
      else
        output:insert(item)
        index = index + 1
      end
    else
      output:insert(item)
      index = index + 1
    end
  end
  return output
end

local function expand_inlines(inlines)
  return expand_inlines_with(inlines, glossary_reference)
end

local function expand_heading(header)
  -- Quarto derives website sidebars and tables of contents from headings.
  -- Tooltip links inside a heading are copied into that navigation and can
  -- create styled or nested anchors that disturb TOC indentation. Resolve
  -- wiki links to plain heading text before the general inline pass instead.
  header.content = expand_inlines_with(header.content, heading_reference)
  return header
end

-- A placeholder may override the project option, for example on a website's
-- shared glossary page: ::: {.glossary include-unused="true"}
local function placeholder_lists_all(div)
  return meta_bool(div.attributes["include-unused"], settings.include_unused)
end

-- Used entries are printed together with the entries their `see` and
-- `see-also` fields name, so a cross-reference in a list always has a target.
local function printed_ids(include_all)
  local printed = {}
  local pending = pandoc.List({})
  for _, entry in ipairs(registry.ordered) do
    if include_all or used[entry.id] then
      printed[entry.id] = true
      pending:insert(entry)
    end
  end
  while #pending > 0 do
    local entry = pending:remove()
    for _, related_ids in ipairs({entry.see, entry.see_also}) do
      for _, related in ipairs(related_ids) do
        if not printed[related] then
          printed[related] = true
          pending:insert(registry.current[related])
        end
      end
    end
  end
  return printed
end

local function entries_to_print(kind, include_all)
  local printed = printed_ids(include_all)
  local entries = pandoc.List({})
  for _, entry in ipairs(registry.ordered) do
    local matches_kind = (kind == "acronym" and entry.kind == "acronym") or
      (kind == "term" and entry.kind ~= "acronym")
    if matches_kind and printed[entry.id] then
      entries:insert(entry)
    end
  end
  return entries
end

local function html_entry_list(entries, extra_class)
  local items = pandoc.List({})
  for _, entry in ipairs(entries) do
    local label = default_display(entry)
    if entry.kind == "acronym" and entry.long ~= "" then
      label = entry.short .. " (" .. entry.long .. ")"
    end
    local label_inlines = markdown_inlines(label)
    if entry.symbol ~= "" then
      label_inlines:insert(pandoc.Space())
      label_inlines:insert(pandoc.Str("("))
      for _, inline in ipairs(markdown_inlines(entry.symbol)) do
        label_inlines:insert(inline)
      end
      label_inlines:insert(pandoc.Str(")"))
    end
    local term = pandoc.Span(label_inlines,
      pandoc.Attr("glossary-" .. entry.id, {"glossary-entry"}))
    local description = markdown_blocks(entry.definition)
    local function append_related(title, related)
      if #related == 0 then
        return
      end
      local inlines = pandoc.Inlines({pandoc.Emph({pandoc.Str(title .. ":")}),
        pandoc.Space()})
      for index, related_id in ipairs(related) do
        local related_entry = registry.current[related_id]
        if index > 1 then
          inlines:insert(pandoc.Str(","))
          inlines:insert(pandoc.Space())
        end
        inlines:insert(pandoc.Link(markdown_inlines(default_display(related_entry)),
          "#glossary-" .. related_id))
      end
      description:insert(pandoc.Para(inlines))
    end
    append_related("See", entry.see)
    append_related("See also", entry.see_also)
    -- One definition holding every block, so the list grid keeps one <dd>
    -- per <dt> even with several paragraphs or a See line.
    items:insert({{term}, {description}})
  end
  return pandoc.Div({pandoc.DefinitionList(items)},
    pandoc.Attr("", {"glossary-list", extra_class}))
end

local function append_html_section(blocks, entries, level, title, identifier,
    extra_class)
  if #entries == 0 then
    return
  end
  blocks:insert(pandoc.Header(level, markdown_inlines(title),
    pandoc.Attr(identifier)))
  blocks:insert(html_entry_list(entries, extra_class))
end

local function html_glossary(div)
  local level = tonumber(div.attributes.level) or settings.heading_level
  local include_all = placeholder_lists_all(div)
  local blocks = pandoc.Blocks({})
  append_html_section(blocks, entries_to_print("acronym", include_all), level,
    div.attributes["acronym-title"] or settings.acronym_title,
    div.attributes["acronym-id"] or "acronyms", "acronym-list")
  append_html_section(blocks, entries_to_print("term", include_all), level,
    div.attributes.title or settings.title,
    div.identifier ~= "" and div.identifier or "glossary", "term-list")
  return blocks
end

local function latex_glossary(div)
  local title = div.attributes.title or settings.title
  local acronym_title = div.attributes["acronym-title"] or settings.acronym_title
  local include_all = placeholder_lists_all(div)
  local commands = pandoc.List({})
  if include_all and settings.latex_backend ~= "bib2gls" then
    commands:insert("\\glsaddall")
  elseif settings.latex_backend ~= "bib2gls" then
    -- bib2gls selects these itself ("recorded and deps").
    local printed = printed_ids(false)
    for _, entry in ipairs(registry.ordered) do
      if printed[entry.id] and not used[entry.id] then
        commands:insert("\\glsadd{" .. entry.id .. "}")
      end
    end
  end
  local print_command
  if settings.latex_backend == "noidx" then
    print_command = "\\printnoidxglossary"
  elseif settings.latex_backend == "makeindex" then
    print_command = "\\printglossary"
  else
    print_command = "\\printunsrtglossary"
  end
  local sort_option = settings.latex_backend == "noidx" and
    ",sort=" .. settings.latex_sort or ""
  if #entries_to_print("acronym", include_all) > 0 then
    commands:insert(print_command .. "[type=\\acronymtype,title={" ..
      latex_escape(acronym_title) .. "}" .. sort_option .. "]")
  end
  if #entries_to_print("term", include_all) > 0 then
    commands:insert(print_command .. "[title={" ..
      latex_escape(title) .. "}" .. sort_option .. "]")
  end
  return pandoc.RawBlock("latex", table.concat(commands, "\n"))
end

local function other_glossary(div)
  return html_glossary(div)
end

local function replace_glossary(div)
  if not div.classes:includes("glossary") then
    return nil
  end
  if quarto.doc.is_format("latex") or FORMAT:match("latex") then
    return latex_glossary(div)
  end
  if quarto.doc.is_format("html") or FORMAT:match("html") then
    return html_glossary(div)
  end
  return other_glossary(div)
end

local function markdown_blocks_to_latex(text)
  local parsed = pandoc.read(text, "markdown")
  local has_citations = false
  parsed:walk({Cite = function(cite)
    has_citations = true
    for _, citation in ipairs(cite.citations) do
      glossary_citation_ids[citation.id] = true
    end
  end})
  if has_citations and pandoc.utils.citeproc then
    local fragment = pandoc.Pandoc(parsed.blocks, document_meta)
    local ok, processed = pcall(pandoc.utils.citeproc, fragment)
    if not ok then
      fail("cannot process citation in glossary definition: " ..
        tostring(processed))
    end
    processed = processed:walk({Div = function(div)
      if div.identifier == "refs" then
        return {}
      end
    end})
    parsed = processed
  end
  return trim(pandoc.write(parsed, "latex"))
end

local function add_glossary_nocite(meta)
  local ids = pandoc.List({})
  for id in pairs(glossary_citation_ids) do
    ids:insert(id)
  end
  table.sort(ids)
  if #ids == 0 then
    return
  end
  local markers = pandoc.List({})
  for _, id in ipairs(ids) do
    markers:insert("@" .. id)
  end
  local parsed = pandoc.read(table.concat(markers, "; "), "markdown")
  local citations = pandoc.utils.blocks_to_inlines(parsed.blocks)
  if meta.nocite ~= nil then
    local combined = pandoc.Inlines(meta.nocite)
    combined:insert(pandoc.Space())
    for _, inline in ipairs(citations) do
      combined:insert(inline)
    end
    meta.nocite = combined
  else
    meta.nocite = citations
  end
end

local function append_option(options, name, value, rich)
  if value == nil or value == "" then
    return
  end
  local rendered = rich and markdown_blocks_to_latex(value) or
    latex_escape(value)
  options:insert(name .. "={" .. rendered .. "}")
end

local function append_related_options(options, entry)
  if #entry.see > 0 then
    options:insert("see={" .. table.concat(entry.see, ",") .. "}")
  end
  if #entry.see_also > 0 then
    if settings.latex_package ~= "glossaries-extra" then
      fail("entry '" .. entry.id ..
        "' uses see-also, which requires latex-package: glossaries-extra")
    end
    options:insert("seealso={" .. table.concat(entry.see_also, ",") .. "}")
  end
end

local function latex_entry_definition(entry)
  local options = pandoc.List({})
  if entry.kind == "acronym" then
    append_option(options, "description", entry.definition, true)
    append_option(options, "shortplural", entry.short_plural, false)
    append_option(options, "longplural", entry.long_plural, false)
    if entry.text ~= entry.short then
      append_option(options, "text", entry.text, false)
    end
    append_option(options, "symbol", entry.symbol, true)
    append_related_options(options, entry)
    local prefix = #options > 0 and "[" .. table.concat(options, ",") .. "]" or ""
    return "\\newacronym" .. prefix .. "{" .. entry.id .. "}{" ..
      latex_escape(entry.short) .. "}{" .. latex_escape(entry.long) .. "}"
  end

  append_option(options, "name", entry.term, false)
  append_option(options, "text", entry.text, false)
  append_option(options, "plural", entry.plural, false)
  append_option(options, "first", entry.first, false)
  append_option(options, "firstplural", entry.first_plural, false)
  append_option(options, "symbol", entry.symbol, true)
  append_option(options, "sort", entry.sort, false)
  append_related_options(options, entry)
  return "\\longnewglossaryentry{" .. entry.id .. "}{" ..
    table.concat(options, ",") .. "}{" ..
    markdown_blocks_to_latex(entry.definition) .. "}"
end

local function bib_field(fields, name, value, rich)
  if value == nil or value == "" then
    return
  end
  local rendered = rich and markdown_blocks_to_latex(value) or
    latex_escape(value)
  fields:insert("  " .. name .. " = {" .. rendered .. "}")
end

local function bib_related_field(fields, name, values)
  if #values > 0 then
    fields:insert("  " .. name .. " = {" .. table.concat(values, ",") .. "}")
  end
end

local function bib2gls_database()
  local records = pandoc.List({})
  for _, entry in ipairs(registry.ordered) do
    local fields = pandoc.List({})
    local entry_type
    if entry.kind == "acronym" then
      entry_type = "acronym"
      bib_field(fields, "short", entry.short, false)
      bib_field(fields, "long", entry.long, false)
      bib_field(fields, "shortplural", entry.short_plural, false)
      bib_field(fields, "longplural", entry.long_plural, false)
      bib_field(fields, "description", entry.definition, true)
    else
      entry_type = "entry"
      bib_field(fields, "name", entry.term, false)
      bib_field(fields, "text", entry.text, false)
      bib_field(fields, "plural", entry.plural, false)
      bib_field(fields, "first", entry.first, false)
      bib_field(fields, "firstplural", entry.first_plural, false)
      bib_field(fields, "description", entry.definition, true)
    end
    bib_field(fields, "symbol", entry.symbol, true)
    bib_related_field(fields, "see", entry.see)
    bib_related_field(fields, "seealso", entry.see_also)
    records:insert("@" .. entry_type .. "{" .. entry.id .. ",\n" ..
      table.concat(fields, ",\n") .. "\n}")
  end
  return table.concat(records, "\n\n") .. "\n"
end

local function bib2gls_path()
  if settings.bib2gls_file ~= "" then
    return resolve_source_path(settings.bib2gls_file)
  end
  local input = tostring(quarto.doc.input_file or "document.qmd")
  local directory = pandoc.path.directory(input)
  local stem = pandoc.path.filename(input):gsub("%.[^.]+$", "")
  return pandoc.path.join({directory, "_quarto-glossary-" .. stem .. ".bib"})
end

local function write_bib2gls_database()
  local path = bib2gls_path()
  local handle, message = io.open(path, "w")
  if not handle then
    fail("cannot write bib2gls database " .. path .. ": " .. tostring(message))
  end
  handle:write(bib2gls_database())
  handle:close()
  local resource = path:gsub("\\", "/"):match("([^/]+)$"):gsub("%.bib$", "")
  return resource
end

local function latex_definitions()
  local lines = pandoc.List({})
  if settings.latex_backend == "noidx" then
    lines:insert("\\makenoidxglossaries")
  elseif settings.latex_backend == "makeindex" then
    lines:insert("\\makeglossaries")
  end

  if settings.latex_style ~= "" then
    lines:insert("\\setglossarystyle{" ..
      latex_escape(settings.latex_style) .. "}")
  end
  if registry.has_acronyms and settings.acronym_style ~= "" then
    if settings.latex_package == "glossaries-extra" then
      lines:insert("\\setabbreviationstyle[acronym]{" ..
        latex_escape(settings.acronym_style) .. "}")
    else
      lines:insert("\\setacronymstyle{" ..
        latex_escape(settings.acronym_style) .. "}")
    end
  end

  if settings.latex_backend == "bib2gls" then
    local selection = (settings.include_unused or document_lists_all) and
      "all" or "recorded and deps"
    local save_locations = settings.latex_location_lists and "true" or "false"
    local bib2gls_sort = {
      letter = "letter-nocase",
      case = "letter-case",
      def = "none",
      use = "use",
    }
    local resource_options = pandoc.List({
      "src={" .. write_bib2gls_database() .. "}",
      "selection={" .. selection .. "}",
    })
    if settings.latex_sort ~= "word" then
      resource_options:insert("sort={" .. bib2gls_sort[settings.latex_sort] .. "}")
    end
    resource_options:insert("save-locations={" .. save_locations .. "}")
    lines:insert("\\GlsXtrLoadResources[" ..
      table.concat(resource_options, ",") .. "]")
    return table.concat(lines, "\n")
  end

  for _, entry in ipairs(registry.ordered) do
    lines:insert(latex_entry_definition(entry))
  end
  return table.concat(lines, "\n")
end

local function latex_package_options()
  local options = pandoc.List({"acronym", "toc", "nopostdot"})
  if settings.latex_backend == "bib2gls" then
    options:insert("record")
  elseif not settings.latex_location_lists then
    options:insert("nonumberlist")
  end
  return table.concat(options, ",")
end

local function configure_output()
  if quarto.doc.is_format("html") or FORMAT:match("html") then
    local dependency = {
      name = "quarto-glossary",
      version = VERSION,
      stylesheets = {"glossary.css"},
    }
    if settings.html_definition_display == "balloon" then
      dependency.scripts = {"glossary.js"}
    end
    quarto.doc.add_html_dependency(dependency)
  elseif quarto.doc.is_format("latex") or FORMAT:match("latex") then
    if settings.load_latex_package then
      quarto.doc.use_latex_package(settings.latex_package,
        latex_package_options())
    end
    quarto.doc.include_text("in-header", latex_definitions())
  end
end

function Pandoc(doc)
  used = {}
  seen = {}
  document_meta = doc.meta
  glossary_citation_ids = {}
  included_metadata_patterns = {}
  registry = load_registry(doc.meta)
  doc = doc:walk({Blocks = strip_included_metadata})
  -- A page with its own glossary list keeps in-page links.
  document_has_glossary = false
  document_lists_all = false
  doc:walk({Div = function(div)
    if div.classes:includes("glossary") then
      document_has_glossary = true
      document_lists_all = document_lists_all or placeholder_lists_all(div)
    end
  end})
  configure_output()
  add_glossary_nocite(doc.meta)

  -- Keep headings structurally plain so Quarto-generated navigation never
  -- inherits tooltip links or positioning styles. Heading keys still count
  -- as uses. The next walk expands references in ordinary body content.
  doc = doc:walk({Header = expand_heading})
  doc = doc:walk({Inlines = expand_inlines})

  -- References have now been recorded, so a glossary placeholder can appear
  -- before or after the prose that uses its entries.
  doc = doc:walk({Div = replace_glossary})
  return doc
end
