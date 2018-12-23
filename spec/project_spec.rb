# frozen_string_literal: true

RSpec.describe 'RuboCop Project', type: :feature do
  let(:cop_names) do
    RuboCop::Cop::Cop
      .registry
      .without_department(:Test)
      .without_department(:InternalAffairs)
      .cops
      .map(&:cop_name)
  end

  shared_context 'configuration file' do |config_path|
    subject(:config) { RuboCop::ConfigLoader.load_file(config_path) }

    let(:configuration_keys) { config.keys }
    let(:raw_configuration) { config.to_h.values }
  end

  describe 'default configuration file' do
    include_context 'configuration file', 'config/default.yml'

    it 'has configuration for all cops' do
      expect(configuration_keys).to match_array(%w[AllCops Rails] + cop_names)
    end

    it 'has a nicely formatted description for all cops' do
      cop_names.each do |name|
        description = config[name]['Description']
        expect(description.nil?).to be(false)
      end
    end

    it 'sorts configuration keys alphabetically' do
      expected = configuration_keys.sort
      configuration_keys.each_with_index do |key, idx|
        expect(key).to eq expected[idx]
      end
    end

    it 'has a SupportedStyles for all EnforcedStyle ' \
      'and EnforcedStyle is valid' do
      errors = []
      cop_names.each do |name|
        enforced_styles = config[name]
                          .select { |key, _| key.start_with?('Enforced') }
        enforced_styles.each_key do |style_name|
          supported_key = RuboCop::Cop::Util.to_supported_styles(style_name)
          valid = config[name][supported_key]
          errors.push("#{supported_key} is missing for #{name}") unless valid
        end
      end

      raise errors.join("\n") unless errors.empty?
    end

    it 'does not have nay duplication' do
      fname = File.expand_path('../config/default.yml', __dir__)
      content = File.read(fname)
      RuboCop::YAMLDuplicationChecker.check(content, fname) do |key1, key2|
        raise "#{fname} has duplication of #{key1.value} " \
              "on line #{key1.start_line} and line #{key2.start_line}"
      end
    end
  end

  describe 'cop message' do
    let(:cops) { RuboCop::Cop::Cop.all }

    it 'end with a period or a question mark' do
      cops.each do |cop|
        begin
          msg = cop.const_get(:MSG)
        rescue NameError
          next
        end
        expect(msg).to match(/(?:[.?]|(?:\[.+\])|%s)$/)
      end
    end
  end

  describe 'changelog' do
    subject(:changelog) do
      path = File.join(File.dirname(__FILE__), '..', 'CHANGELOG.md')
      File.read(path)
    end

    let(:lines) { changelog.each_line }

    let(:non_reference_lines) do
      lines.take_while { |line| !line.start_with?('[@') }
    end

    it 'has newline at end of file' do
      expect(changelog.end_with?("\n")).to be true
    end

    it 'has either entries, headers, or empty lines' do
      expect(non_reference_lines).to all(match(/^(\*|#|$)/))
    end

    it 'has link definitions for all implicit links' do
      implicit_link_names = changelog.scan(/\[([^\]]+)\]\[\]/).flatten.uniq
      implicit_link_names.each do |name|
        expect(changelog.include?("[#{name}]: http"))
          .to be(true), "CHANGELOG.md is missing a link for #{name}. " \
                        'Please add this link to the bottom of the file.'
      end
    end

    describe 'entry' do
      subject(:entries) { lines.grep(/^\*/).map(&:chomp) }

      it 'has a whitespace between the * and the body' do
        expect(entries).to all(match(/^\* \S/))
      end

      context 'after version 0.14.0' do
        let(:lines) do
          changelog.each_line.take_while do |line|
            !line.start_with?('## 0.14.0')
          end
        end

        it 'has a link to the contributors at the end' do
          expect(entries).to all(match(/\(\[@\S+\]\[\](?:, \[@\S+\]\[\])*\)$/))
        end
      end

      describe 'link to related issue' do
        let(:issues) do
          entries.map do |entry|
            entry.match(/\[(?<number>[#\d]+)\]\((?<url>[^\)]+)\)/)
          end.compact
        end

        it 'has an issue number prefixed with #' do
          issues.each do |issue|
            expect(issue[:number]).to match(/^#\d+$/)
          end
        end

        it 'has a valid URL' do
          issues.each do |issue|
            number = issue[:number].gsub(/\D/, '')
            pattern = %r{^https://github\.com/rubocop-hq/rubocop/(?:issues|pull)/#{number}$} # rubocop:disable Metrics/LineLength
            expect(issue[:url]).to match(pattern)
          end
        end

        it 'has a colon and a whitespace at the end' do
          entries_including_issue_link = entries.select do |entry|
            entry.match(/^\*\s*\[/)
          end

          expect(entries_including_issue_link).to all(include('): '))
        end
      end

      describe 'contributor name' do
        subject(:contributor_names) { lines.grep(/\A\[@/).map(&:chomp) }

        it 'has a unique contributor name' do
          expect(contributor_names.uniq.size).to eq contributor_names.size
        end
      end

      describe 'body' do
        let(:bodies) do
          entries.map do |entry|
            entry
              .gsub(/`[^`]+`/, '``')
              .sub(/^\*\s*(?:\[.+?\):\s*)?/, '')
              .sub(/\s*\([^\)]+\)$/, '')
          end
        end

        it 'does not start with a lower case' do
          bodies.each do |body|
            expect(body).not_to match(/^[a-z]/)
          end
        end

        it 'ends with a punctuation' do
          expect(bodies).to all(match(/[\.\!]$/))
        end
      end
    end
  end

  describe 'requiring all of `lib` with verbose warnings enabled' do
    it 'emits no warnings' do
      allowed = lambda do |line|
        line =~ /warning: private attribute\?$/ && RUBY_VERSION < '2.3'
      end

      warnings = `ruby -Ilib -w -W2 lib/rubocop.rb 2>&1`
                 .lines
                 .grep(%r{/lib/rubocop}) # ignore warnings from dependencies
                 .reject(&allowed)

      expect(warnings.empty?).to be(true)
    end
  end
end
