package App::Netdisco::Util::Python;

# Python工具模块
# 提供Python环境管理和命令执行功能

use Dancer qw/:syntax :script/;

use Path::Class;
use File::ShareDir 'dist_dir';
use Alien::ultraviolet;

use base 'Exporter';
our @EXPORT = ();
our @EXPORT_OK = qw/py_install py_cmd/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);

# 获取cipactli命令参数
# 构建ultraviolet命令的基础参数
sub cipactli {
  my $uv = Alien::ultraviolet->uv;
  my $cipactli = Path::Class::Dir->new( dist_dir('App-Netdisco') )
    ->subdir('python')->subdir('netdisco')->stringify;

  return ($uv, '--no-cache', '--no-progress', '--quiet', '--project', $cipactli);
}

# Python安装
# 同步Python依赖
sub py_install {
  return (cipactli(), 'sync');
}

# Python命令执行
# 运行Python命令
sub py_cmd {
  return (cipactli(), 'run', @_);
}

true;
