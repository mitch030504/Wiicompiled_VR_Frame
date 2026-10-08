import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'steam-frame-install.sh'
TEXT = SCRIPT.read_text()
CODE = TEXT.split("<<'FRAME_FILES_PY'\n", 1)[1].split('\nFRAME_FILES_PY', 1)[0]
OPERATIONS = {'__name__': 'frame_tests'}
exec(compile(CODE, str(SCRIPT), 'exec'), OPERATIONS)


class FrameInstallerTests(unittest.TestCase):
    def test_source_membership_preserves_user_data_and_unchanged_timestamps(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            source, live = root / 'source', root / 'live'
            source.mkdir()
            live.mkdir()
            (source / 'keep.cpp').write_text('same')
            (live / 'keep.cpp').write_text('same')
            os.utime(live / 'keep.cpp', (100, 100))
            (live / 'removed.cpp').write_text('old')
            (live / '.release-files').write_text('keep.cpp\nremoved.cpp\n')
            (live / 'Assets').mkdir()
            (live / 'Assets/main.dol').write_text('disc')
            (live / 'native-build').mkdir()
            (live / 'native-build/cache').write_text('cache')
            OPERATIONS['sync_source'](source, live)
            self.assertFalse((live / 'removed.cpp').exists())
            self.assertEqual(100, (live / 'keep.cpp').stat().st_mtime)
            self.assertEqual('disc', (live / 'Assets/main.dol').read_text())
            self.assertEqual('cache', (live / 'native-build/cache').read_text())

    def test_paths_replace_only_the_right_section_and_escape_values(self):
        with tempfile.TemporaryDirectory() as home, patch.dict(os.environ, HOME=home):
            config = Path(home) / '.local/share/WiiCompiled/Config.toml'
            config.parent.mkdir(parents=True)
            config.write_text('[other]\ndvd_root = "untouched"\n[ "paths" ] # paths\n"dvd_root" = "old"\n[video]\nscale = 2')
            value = '/media/My Games/a"b\\c\nfolder'
            OPERATIONS['set_path']('dvd_root', value)
            parsed = tomllib.loads(config.read_text())
            self.assertEqual(value, parsed['paths']['dvd_root'])
            self.assertEqual('untouched', parsed['other']['dvd_root'])
            self.assertEqual(2, parsed['video']['scale'])
            OPERATIONS['set_path']('retro_rewind_root', 'packs/My Pack')
            self.assertEqual(str(Path(home) / 'packs/My Pack'), tomllib.loads(config.read_text())['paths']['retro_rewind_root'])

    def test_ssh_keeps_argument_boundaries(self):
        function = TEXT.split('on_frame() {', 1)[1].split('\n}\n', 1)[0]
        script = 'ssh_opts=(); frame=remote\nssh() { bash -c "${@: -1}"; }\non_frame() {' + function + '\n}\non_frame "$@"'
        arguments = ['/media/My Games/disc', "quote'and$characters", '']
        result = subprocess.run(['bash', '-c', script, 'test', *arguments], input='printf "%s\\0" "$@"\n', capture_output=True, text=True, check=True)
        self.assertEqual('\0'.join(arguments) + '\0', result.stdout)

    def test_lock_blocks_a_second_installer(self):
        locking = TEXT.split('command -v flock >/dev/null || fail', 1)[1].split('\n', 1)[1].split('command -v python3', 1)[0]
        setup = 'work_dir=$1; fail() { echo "$*" >&2; exit 1; }\n'
        with tempfile.TemporaryDirectory() as root:
            holder = subprocess.Popen(['bash', '-c', setup + locking + '\necho ready; read -r', 'test', root], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual('ready\n', holder.stdout.readline())
                contender = subprocess.run(['bash', '-c', setup + locking, 'test', root], capture_output=True, text=True)
                self.assertEqual(1, contender.returncode)
                self.assertIn('Another install or update', contender.stderr)
            finally:
                holder.communicate('\n')
            self.assertEqual(0, subprocess.run(['bash', '-c', setup + locking, 'test', root]).returncode)

    def test_unsigned_payload_stops_before_translation(self):
        build = SCRIPT.with_name('local-build.sh').read_text()
        block = build.split('if (( builds_retro && !skip_retro_wfc_payload )); then', 1)[1].split('\nfi', 1)[0]
        setup = 'builds_retro=1; skip_retro_wfc_payload=0; retro_wfc_offline_dir="/payload folder"\n'
        check = 'translator() { [[ "$1" == validate-retro-wfc-payload && "$2" == --directory && "$3" == "/payload folder" ]] || exit 99; return 23; }\n'
        result = subprocess.run(['bash', '-e', '-c', setup + check + block + '\necho translated'], capture_output=True, text=True)
        self.assertEqual(23, result.returncode)
        self.assertNotIn('translated', result.stdout)

    def test_config_function_can_be_sent_to_remote_bash(self):
        function = TEXT.split('frame_files() {', 1)[1].split('\n}\n', 1)[0]
        with tempfile.TemporaryDirectory() as home:
            result = subprocess.run(['bash', '-s', '--', 'config', 'dvd_root', '/new disc'], input='frame_files() {' + function + '\n}\nframe_files "$@"\n', text=True, capture_output=True, env={**os.environ, 'HOME': home})
            self.assertEqual(0, result.returncode, result.stderr)
            config = Path(home) / '.local/share/WiiCompiled/Config.toml'
            self.assertEqual('/new disc', tomllib.loads(config.read_text())['paths']['dvd_root'])


if __name__ == '__main__':
    unittest.main()
