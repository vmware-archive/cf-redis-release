require 'spec_helper'

require 'london_blob_checker/package'

RSpec.describe LondonBlobChecker::Package do
  subject(:instance) { described_class.new(path) }

  describe 'filename' do
    let(:path) { 'nginx/nginx-1.2.3.tar.gz' }
    its(:filename) { is_expected.to eql('nginx-1.2.3.tar.gz') }
  end

  describe 'name' do
    context 'with name-d.d.d-pddd.fmt style' do
      let(:path) { 'ruby/ruby-1.2.3-p456.tar.gz' }
      its(:name) { is_expected.to eql('ruby') }
    end
    context 'with name-d.d.d.fmt style' do
      let(:path) { 'nginx/nginx-1.2.3.tar.gz' }
      its(:name) { is_expected.to eql('nginx') }
    end
    context 'with named.d.arch.fmt style' do
      let(:path) { 'go/go1.2.linux-amd64.tar.gz' }
      its(:name) { is_expected.to eql('go') }
    end
  end

  describe 'version' do
    context 'with name-d.d.d-pddd.fmt style' do
      let(:path) { 'ruby/ruby-1.2.3-p456.tar.gz' }
      its(:version) { is_expected.to eql('1.2.3-p456') }
    end
    context 'with name-d.d.d.fmt style' do
      let(:path) { 'nginx/nginx-1.2.3.tar.gz' }
      its(:version) { is_expected.to eql('1.2.3') }
    end
    context 'with named.d.arch.fmt style' do
      let(:path) { 'go/go1.2.linux-amd64.tar.gz' }
      its(:version) { is_expected.to eql('1.2') }
    end
    context 'with named-d.dd.tar.gz' do
      let(:path) { 'pcre-8.34.tar.gz' }
      its(:version) { is_expected.to eql('8.34') }
    end
  end

  describe 'format' do
    context 'with gzip archive' do
      let(:path) { 'ruby/ruby-1.2.3-p456.tar.gz' }
      its(:format) { is_expected.to eql('tar.gz') }
    end
    context 'with bz2 archive' do
      let(:path) { 'nginx/nginx-1.2.3.tar.bz2' }
      its(:format) { is_expected.to eql('tar.bz2') }
    end
    context 'with zip archive' do
      let(:path) { 'nginx/nginx-1.2.3.zip' }
      its(:format) { is_expected.to eql('zip') }
    end
    context 'with tar archive' do
      let(:path) { 'go/go1.2.linux-amd64.tar' }
      its(:format) { is_expected.to eql('tar') }
    end
  end

  describe 'platform' do
    context 'with name-d.d.d-pddd.fmt style' do
      let(:path) { 'ruby/ruby-1.2.3-p456.tar.gz' }
      its(:platform) { is_expected.to be_nil }
    end
    context 'with name-d.d.d.fmt style' do
      let(:path) { 'nginx/nginx-1.2.3.tar.gz' }
      its(:platform) { is_expected.to be_nil }
    end
    context 'with named.d.arch.fmt style' do
      let(:path) { 'go/go1.2.linux-amd64.tar.gz' }
      its(:platform) { is_expected.to eql('linux-amd64') }
    end
  end
end
