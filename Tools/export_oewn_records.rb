#!/usr/bin/env ruby
# frozen_string_literal: true

# Convert Open English WordNet's YAML source into the small JSONL shape used by
# build_dictionary_index.py. This is a build-time tool; no YAML parser is
# included in the iOS app.

require "json"
require "yaml"

root = ARGV.fetch(0) do
  warn "Usage: ruby Tools/export_oewn_records.rb WORDNET_ROOT OUTPUT_JSONL"
  exit 2
end
output = ARGV.fetch(1) do
  warn "Usage: ruby Tools/export_oewn_records.rb WORDNET_ROOT OUTPUT_JSONL"
  exit 2
end

root = File.expand_path(root)
unless File.directory?(File.join(root, "src", "yaml"))
  abort "Open English WordNet src/yaml not found: #{root}"
end

def list(value)
  value.is_a?(Array) ? value : (value.nil? ? [] : [value])
end

def read_yaml(path)
  YAML.safe_load(
    File.read(path, encoding: "UTF-8"),
    permitted_classes: [Symbol],
    aliases: true
  ) || {}
rescue Psych::Exception => error
  abort "Unable to parse #{path}: #{error.message}"
end

def normalize(value)
  value.to_s
       .unicode_normalize(:nfkd)
       .gsub(/\p{Mn}/, "")
       .tr("’‘＇–—", "'''--")
       .downcase
       .split
       .map { |token| token.gsub(/^[.,;:!?()\[\]{}\"“”…]+|[.,;:!?()\[\]{}\"“”…]+$/, "") }
       .reject(&:empty?)
       .join(" ")
end

yaml_root = File.join(root, "src", "yaml")
synsets = {}
Dir.glob(File.join(yaml_root, "{adj.*,adv.all,noun.*,verb.*}.yaml")).sort.each do |path|
  read_yaml(path).each do |id, record|
    next unless record.is_a?(Hash)

    synsets[id.to_s] = {
      "members" => list(record["members"]).map(&:to_s),
      "definitions" => list(record["definition"]).map(&:to_s),
      "examples" => list(record["example"]).map(&:to_s),
      "antonym_ids" => list(record["antonym"]).map(&:to_s),
      "part_of_speech" => record["partOfSpeech"].to_s
    }
  end
end

lemmas = Hash.new do |hash, key|
  hash[key] = {
    "headword" => key,
    "partOfSpeech" => [],
    "synset_ids" => [],
    "pronunciation" => []
  }
end

Dir.glob(File.join(yaml_root, "entries-*.yaml")).sort.each do |path|
  read_yaml(path).each do |lemma, by_part_of_speech|
    next unless by_part_of_speech.is_a?(Hash)

    item = lemmas[lemma.to_s]
    by_part_of_speech.each do |part_of_speech, record|
      next unless record.is_a?(Hash)

      item["partOfSpeech"] << part_of_speech.to_s
      list(record["sense"]).each do |sense|
        next unless sense.is_a?(Hash)

        synset_id = sense["synset"].to_s
        item["synset_ids"] << synset_id unless synset_id.empty?
      end
      list(record["pronunciation"]).each do |pronunciation|
        next unless pronunciation.is_a?(Hash)

        item["pronunciation"] << pronunciation["value"].to_s
      end
    end
  end
end

File.open(output, "w", encoding: "UTF-8") do |handle|
  lemmas.each_value do |item|
    headword = item["headword"]
    headword_key = normalize(headword)
    next if headword_key.empty?

    definitions = []
    examples = []
    synonyms = []
    antonyms = []
    item["synset_ids"].uniq.each do |synset_id|
      synset = synsets[synset_id]
      next unless synset

      definitions.concat(synset["definitions"])
      examples.concat(synset["examples"])
      synset["members"].each do |member|
        synonyms << member unless normalize(member) == headword_key
      end
      synset["antonym_ids"].each do |antonym_id|
        target = synsets[antonym_id]
        antonyms.concat(target["members"]) if target
      end
    end

    record = {
      "headword" => headword,
      "partOfSpeech" => item["partOfSpeech"].uniq.map { |value| "#{value}." }.join("/"),
      "definitions" => definitions.uniq.first(20),
      "examples" => examples.uniq.first(20),
      "synonyms" => synonyms.uniq.reject { |value| normalize(value) == headword_key }.first(20),
      "antonyms" => antonyms.uniq.reject { |value| normalize(value) == headword_key }.first(20)
    }
    handle.puts(JSON.generate(record))
  end
end

warn "Generated Open English WordNet JSONL: #{output} (#{lemmas.length} headwords)"
