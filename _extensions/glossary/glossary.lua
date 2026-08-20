-- A Quarto glossary filter using Obsidian-style wiki links.
--
-- References:
--   [[entry-id]]
--   [[entry-id|custom display text]]
--
-- Glossary placeholder:
--   ::: {.glossary}
--   :::

local registry = nil
local settings = nil
local used = {}

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

  entry.status = row_value(row, {"status"}, "current"):lower()
  entry.kind = row_value(row, {"kind", "type"}, "term"):lower()
  entry.term = row_value(row, {"term", "name"}, "")
  entry.short = row_value(row, {"short", "abbreviation", "acronym"}, "")
  entry.long = row_value(row, {"long", "expansion"}, "")
  entry.definition = row_value(row,
    {"description", "definition", "tooltip"}, "")
  entry.tooltip = row_value(row,
    {"tooltip", "description", "definition"}, "")
  entry.replacement = row_value(row, {"replacement", "use", "not"}, "")
  entry.sort = row_value(row, {"sort"}, "")

  -- Compatibility with the recovered study schema: acronym rows use `term`
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
  else
    if entry.term == "" then
      fail("entry '" .. entry.id .. "' has no term or name")
    end
    if entry.tooltip == "" then
      entry.tooltip = entry.definition
    end
  end

  if entry.status ~= "retired" and entry.definition == "" then
    fail("entry '" .. entry.id .. "' has no definition")
  end
  if entry.sort == "" then
    entry.sort = entry.short ~= "" and entry.short or entry.term
  end
  return entry
end

local function load_registry(meta)
  local config = meta.glossary
  if config == nil then
    fail("filter requires a glossary metadata block with a path")
  end

  local path = meta_text(config.path, "glossary.yml")
  settings = {
    path = resolve_source_path(path),
    strict = meta_bool(config.strict, true),
    include_unused = meta_bool(config["include-unused"], false),
    link = meta_bool(config.link, true),
    load_latex_package = meta_bool(config["latex-load-package"], true),
    title = meta_text(config.title, "Glossary"),
    acronym_title = meta_text(config["acronym-title"], "Acronyms"),
    heading_level = tonumber(meta_text(config["heading-level"], "1")) or 1,
  }

  local result = {
    current = {},
    retired = {},
    ordered = pandoc.List({}),
    has_acronyms = false,
    has_terms = false,
  }
  for _, row in ipairs(source_rows(decode_source(settings.path))) do
    local entry = normalize_entry(row, settings.path)
    if result.current[entry.id] or result.retired[entry.id] then
      fail("duplicate glossary id '" .. entry.id .. "' in " .. settings.path)
    end
    if entry.status == "retired" then
      result.retired[entry.id] = entry
    else
      result.current[entry.id] = entry
      result.ordered:insert(entry)
      if entry.kind == "acronym" then
        result.has_acronyms = true
      else
        result.has_terms = true
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

local function default_display(entry)
  if entry.kind == "acronym" and entry.short ~= "" then
    return entry.short
  end
  return entry.term
end

local function lookup_entry(id)
  local entry = registry.current[id]
  if entry then
    return entry
  end
  local retired = registry.retired[id]
  if retired then
    local message = "glossary key [[" .. id .. "]] is retired"
    if retired.replacement ~= "" then
      message = message .. "; " .. retired.replacement
    end
    fail(message)
  end
  if settings.strict then
    fail("unknown glossary key [[" .. id .. "]] in " ..
      tostring(quarto.doc.input_file or "the input document"))
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
  if display == "" then
    return pandoc.RawInline("latex", "\\gls{" .. entry.id .. "}")
  end
  return pandoc.RawInline("latex", "\\glslink{" .. entry.id .. "}{" ..
    latex_escape(display) .. "}")
end

local function html_reference(entry, display)
  used[entry.id] = true
  local text = display ~= "" and display or default_display(entry)
  local content = markdown_inlines(text)
  local attributes = {
    {"tabindex", "0"},
    {"data-glossary-id", entry.id},
    {"data-glossary-definition", entry.tooltip},
    {"aria-label", pandoc.utils.stringify(content) .. ": " .. entry.tooltip},
  }
  if settings.link then
    return pandoc.Link(content, "#glossary-" .. entry.id, entry.tooltip,
      pandoc.Attr("", {"glossary-link", "glossary-term"}, attributes))
  end
  return pandoc.Span(content,
    pandoc.Attr("", {"glossary-term"}, attributes))
end

local function other_reference(entry, display)
  used[entry.id] = true
  local text = display ~= "" and display or default_display(entry)
  return pandoc.Link(markdown_inlines(text), "#glossary-" .. entry.id,
    entry.tooltip, pandoc.Attr("", {"glossary-link"}))
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
  local text = display ~= "" and display or default_display(entry)
  return markdown_inlines(text)
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

local function expand_inlines_with(inlines, reference)
  local output = pandoc.Inlines({})
  local index = 1
  while index <= #inlines do
    local item = inlines[index]
    if item.t == "Str" and item.text:find("[[", 1, true) then
      local pieces = {item.text}
      local cursor = index
      local token = table.concat(pieces)
      while not token:find("]]", 1, true) and cursor < #inlines do
        cursor = cursor + 1
        local following = inlines[cursor]
        if following.t == "Space" or following.t == "SoftBreak" then
          table.insert(pieces, " ")
        elseif following.t == "Str" then
          table.insert(pieces, following.text)
        else
          break
        end
        token = table.concat(pieces)
      end
      if token:find("]]", 1, true) then
        expand_text(output, token, reference)
        index = cursor + 1
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

local function entries_to_print()
  if settings.include_unused then
    return registry.ordered
  end
  local entries = pandoc.List({})
  for _, entry in ipairs(registry.ordered) do
    if used[entry.id] then
      entries:insert(entry)
    end
  end
  return entries
end

local function html_glossary(div)
  local title = div.attributes.title or settings.title
  local level = tonumber(div.attributes.level) or settings.heading_level
  local blocks = pandoc.Blocks({
    pandoc.Header(level, markdown_inlines(title),
      pandoc.Attr(div.identifier ~= "" and div.identifier or "glossary"))
  })
  local items = pandoc.List({})
  for _, entry in ipairs(entries_to_print()) do
    local label = default_display(entry)
    if entry.kind == "acronym" and entry.long ~= "" then
      label = entry.short .. " (" .. entry.long .. ")"
    end
    local term = pandoc.Span(markdown_inlines(label),
      pandoc.Attr("glossary-" .. entry.id, {"glossary-entry"}))
    items:insert({{term}, markdown_blocks(entry.definition)})
  end
  blocks:insert(pandoc.Div({pandoc.DefinitionList(items)},
    pandoc.Attr("", {"glossary-list"})))
  return blocks
end

local function latex_glossary(div)
  local title = div.attributes.title or settings.title
  local acronym_title = div.attributes["acronym-title"] or settings.acronym_title
  local commands = pandoc.List({})
  if settings.include_unused then
    commands:insert("\\glsaddall")
  end
  if registry.has_acronyms then
    commands:insert("\\printnoidxglossary[type=\\acronymtype,title={" ..
      latex_escape(acronym_title) .. "}]")
  end
  if registry.has_terms then
    commands:insert("\\printnoidxglossary[title={" ..
      latex_escape(title) .. "}]")
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

local function latex_definitions()
  local lines = pandoc.List({"\\makenoidxglossaries"})
  for _, entry in ipairs(registry.ordered) do
    if entry.kind == "acronym" then
      local option = ""
      if entry.definition ~= "" and entry.definition ~= entry.long then
        option = "[description={" .. latex_escape(entry.definition) .. "}]"
      end
      lines:insert("\\newacronym" .. option .. "{" .. entry.id .. "}{" ..
        latex_escape(entry.short) .. "}{" .. latex_escape(entry.long) .. "}")
    else
      lines:insert("\\newglossaryentry{" .. entry.id .. "}{name={" ..
        latex_escape(entry.term) .. "},description={" ..
        latex_escape(entry.definition) .. "},sort={" ..
        latex_escape(entry.sort) .. "}}")
    end
  end
  return table.concat(lines, "\n")
end

local function configure_output()
  if quarto.doc.is_format("html") or FORMAT:match("html") then
    quarto.doc.add_html_dependency({
      name = "quarto-glossary",
      version = "0.1.1",
      stylesheets = {"glossary.css"},
    })
  elseif quarto.doc.is_format("latex") or FORMAT:match("latex") then
    if settings.load_latex_package then
      quarto.doc.use_latex_package("glossaries", "acronym,nonumberlist,toc")
    end
    quarto.doc.include_text("in-header", latex_definitions())
  end
end

function Pandoc(doc)
  used = {}
  registry = load_registry(doc.meta)
  configure_output()

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
