# encoding: UTF-8

require 'winrm/shells/power_shell'

describe WinRM::Shells::PowerShell do
  let(:retry_limit) { 1 }
  let(:shell_id) { 'bc1bfbba-8215-4a04-b2df-7a3ac0310e16' }
  let(:output) { 'output' }
  let(:command_id) { '4218A578-0F18-4B19-82C3-46B433319126' }
  let(:keepalive_payload) { 'keepalive_payload' }
  let(:command_payload) { 'command_payload' }
  let(:create_shell_payload) { 'create_shell_payload' }
  let(:close_shell_payload) { 'close_shell_payload' }
  let(:cleanup_payload) { 'cleanup_payload' }
  let(:command) { 'command' }
  let(:connection_options) { { max_commands: 100, retry_limit: retry_limit, retry_delay: 0 } }
  let(:transport) { double('transport', send_request: nil) }
  let(:test_data_xml_template) do
    ERB.new(stubbed_response('get_powershell_output_response.xml.erb'))
  end
  let(:test_data) { '<I32 N="RunspaceState">2</I32>' }
  let(:message) do
    WinRM::PSRP::Message.new(
      shell_id,
      WinRM::PSRP::Message::MESSAGE_TYPES[:runspacepool_state],
      test_data,
      command_id
    )
  end
  let(:fragment) { WinRM::PSRP::Fragment.new(1, message.bytes) }
  let(:test_data_stdout) { Base64.strict_encode64(fragment.bytes.pack('C*')) }

  before do
    allow(SecureRandom).to receive(:uuid).and_return(command_id)
    allow_any_instance_of(WinRM::WSMV::CreatePipeline).to receive(:build)
      .and_return(command_payload)
    allow_any_instance_of(WinRM::WSMV::CloseShell).to receive(:build)
      .and_return(close_shell_payload)
    allow_any_instance_of(WinRM::WSMV::InitRunspacePool).to receive(:build)
      .and_return(create_shell_payload)
    allow_any_instance_of(WinRM::WSMV::CleanupCommand).to receive(:build)
      .and_return(cleanup_payload)
    allow_any_instance_of(WinRM::WSMV::KeepAlive).to receive(:build).and_return(keepalive_payload)
    allow_any_instance_of(WinRM::PSRP::PowershellOutputProcessor).to receive(:command_output)
      .with(shell_id, command_id).and_return(output)
    allow(transport).to receive(:send_request).with(create_shell_payload)
      .and_return(REXML::Document.new("<blah Name='ShellId'>#{shell_id}</blah>"))
    allow(transport).to receive(:send_request).with(keepalive_payload)
      .and_return(REXML::Document.new(test_data_xml_template.result(binding)))
  end

  subject { described_class.new(connection_options, transport, Logging.logger['test']) }

  describe '#run' do
    it 'opens a shell and gets shell id' do
      subject.run(command)
      expect(subject.shell_id).to eq shell_id
    end

    it 'sends create shell through transport' do
      expect(transport).to receive(:send_request).with(create_shell_payload)
      subject.run(command)
    end

    it 'sends keepalive shell through transport' do
      expect(transport).to receive(:send_request).with(keepalive_payload)
      subject.run(command)
    end

    it 'returns output from generated command' do
      expect(subject.run(command)).to eq output
    end

    it 'sends command through transport' do
      expect(transport).to receive(:send_request).with(command_payload)
      subject.run(command)
    end

    it 'sends cleanup message through transport' do
      expect(transport).to receive(:send_request).with(cleanup_payload)
      subject.run(command)
    end

    it 'output processor sets powershell uri and streams' do
      allow(WinRM::PSRP::PowershellOutputProcessor).to receive(:new) do |_, _, _, opts|
        expect(opts[:shell_uri]).to be WinRM::WSMV::Header::RESOURCE_URI_POWERSHELL
        expect(opts[:out_streams]).to eq %w(stdout)
      end.and_call_original
      subject.run(command)
    end
  end

  describe '#close' do
    it 'sends close shell through transport' do
      subject.run(command)
      expect(transport).to receive(:send_request).with(close_shell_payload)
      subject.close
    end

    it 'creates a shell closer with powershell uri' do
      allow(WinRM::WSMV::CloseShell).to receive(:new) do |_, opts|
        expect(opts[:shell_uri]).to be WinRM::WSMV::Header::RESOURCE_URI_POWERSHELL
      end.and_call_original
      subject.close
    end
  end
end