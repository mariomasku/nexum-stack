"""GUI installation results must point to the directory created by run_plan_item."""
import ast
import pathlib
import unittest

root = pathlib.Path(__file__).resolve().parents[1]
source = root / 'src/linux/ventana/03-llamadas-al-script.py'
tree = ast.parse(source.read_text(encoding='utf-8'))
function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'item_folder')
namespace = {}
exec(compile(ast.Module(body=[function], type_ignores=[]), str(source), 'exec'), namespace)


class FolderTests(unittest.TestCase):
    def test_created_directory(self):
        for item, folder in [('php:8.5.12', '8.5.12'), ('parche:8.4.1', '8.4.1'),
                             ('rehacer:8.4.27', '8.4'), ('reparar:8.5.12', '8.5.12'),
                             ('xampp:8.2.4-0', '8.2.4-0')]:
            with self.subTest(item=item):
                self.assertEqual(namespace['item_folder'](item), folder)


if __name__ == '__main__':
    unittest.main()
