package App::Netdisco::Web::CustomFields;

# 自定义字段Web模块
# 提供设备自定义字段功能

use Dancer ':syntax';

use App::Netdisco::Web::Plugin;
use App::Netdisco::Util::CustomFields;

# 注册设备自定义字段
foreach my $config (@{setting('custom_fields')->{'device'} || []}) {
  next unless $config->{'name'};

  register_device_details({
    %{$config}, field => ('cf_' . $config->{'name'}), label => ($config->{'label'} || ucfirst $config->{'name'}),
  })
    unless $config->{'hidden'};
}

# 注册设备端口自定义字段
foreach my $config (@{setting('custom_fields')->{'device_port'} || []}) {
  next unless $config->{'name'};

  register_device_port_column({
    position => 'right',    # 或"mid"或"right"
    default  => undef,      # 或"checked"
    %{$config},
    field => ('cf_' . $config->{'name'}),
    label => ($config->{'label'} || ucfirst $config->{'name'}),
  })
    unless $config->{'hidden'};
}

true;
