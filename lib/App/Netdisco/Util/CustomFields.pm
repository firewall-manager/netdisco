package App::Netdisco::Util::CustomFields;

# 自定义字段工具模块
# 用于处理设备和设备端口的自定义字段功能

use App::Netdisco;    # 空操作，仅用于测试

use Dancer ':syntax';
use Dancer::Plugin::DBIC;

use App::Netdisco::DB::ResultSet::Device;
use App::Netdisco::DB::ResultSet::DevicePort;

# 存储设备字段的JSON配置
my %device_fields_json = ();

# 存储内联设备操作列表
my @inline_device_actions = ();

# 存储内联设备端口操作列表
my @inline_device_port_actions = ();

# 处理设备自定义字段配置
foreach my $config (@{setting('custom_fields')->{'device'} || []}) {
  next unless $config->{'name'};
  push @inline_device_actions, $config->{'name'};

  # 如果是JSON列表类型，增加计数
  ++$device_fields_json{$config->{'name'}} if $config->{'json_list'};
}

# 处理设备端口自定义字段配置
foreach my $config (@{setting('custom_fields')->{'device_port'} || []}) {
  next unless $config->{'name'};
  push @inline_device_port_actions, $config->{'name'};
}

{
  package App::Netdisco::DB::ResultSet::Device;

  # 为设备结果集添加自定义字段支持
  sub with_custom_fields {
    my ($rs, $cond, $attrs) = @_;

    return $rs->search_rs($cond, $attrs)->search(
      {},
      {
        '+columns' => {

          # 为每个内联设备操作创建自定义字段列
          map { (
            ('cf_' . $_) => \[

              # 如果是JSON列表类型，使用数组查询；否则使用简单字段查询
              (
                $device_fields_json{$_}
                ? q{ARRAY(SELECT json_array_elements_text((me.custom_fields ->> ?) ::json))::text[]}
                : 'me.custom_fields ->> ?'
              ) => $_
            ]
          ) } @inline_device_actions
        }
      }
    );
  }
}

{
  package App::Netdisco::DB::ResultSet::DevicePort;

  # 为设备端口结果集添加自定义字段支持
  sub with_custom_fields {
    my ($rs, $cond, $attrs) = @_;

    return $rs->search_rs($cond, $attrs)->search(
      {},
      {
        '+columns' => {

          # 为每个内联设备端口操作创建自定义字段列
          map { (('cf_' . $_) => \['me.custom_fields ->> ?' => $_]) } @inline_device_port_actions
        }
      }
    );
  }
}

# 设置内联操作列表，用于前端显示
set('_inline_actions' => [map { 'cf_' . $_ } (@inline_device_actions, @inline_device_port_actions)]);

true;

