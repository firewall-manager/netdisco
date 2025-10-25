package App::Netdisco::Util::Worker;

# 工作进程工具模块
# 提供工作进程相关的辅助功能

use Dancer ':syntax';
use App::Netdisco::JobQueue 'jq_insert';

use Encode 'encode';
use MIME::Base64 'encode_base64';

use Storable 'dclone';
use Data::Visitor::Tiny;

use base 'Exporter';
our @EXPORT = ('queue_hook');

# 队列钩子
# 将钩子事件插入到作业队列中
sub queue_hook {
  my ($hook, $conf) = @_;
  my $extra = {action_conf => dclone($conf->{'with'} || {}), event_data => dclone(vars->{'hook_data'} || {})};

  # 移除to_json无法处理的标量引用
  visit(
    $extra->{'event_data'},
    sub {
      my ($key, $valueref) = @_;
      $$valueref = '' if ref $$valueref eq 'SCALAR';
    }
  );

  jq_insert({action => ('hook::' . lc($conf->{'type'})), extra => encode_base64(encode('UTF-8', to_json($extra)), ''),
  });

  return 1;
}

true;
