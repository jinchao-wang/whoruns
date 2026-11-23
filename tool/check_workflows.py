"""校验 .github/workflows 下的 YAML 能不能被解析。

用 PyYAML 跑一遍：GitHub 遇到语法错误时不会报错提示，
只会把工作流名字显示成文件路径，很容易被忽略过去。
"""
import glob
import sys

import yaml

failed = False
for path in sorted(glob.glob('.github/workflows/*.yml')):
    try:
        data = yaml.safe_load(open(path, encoding='utf-8'))
        name = data.get('name') if isinstance(data, dict) else None
        print(f'OK   {path}  name={name!r}')
    except Exception as e:
        failed = True
        print(f'FAIL {path}: {str(e).replace(chr(10), " | ")}')

sys.exit(1 if failed else 0)
