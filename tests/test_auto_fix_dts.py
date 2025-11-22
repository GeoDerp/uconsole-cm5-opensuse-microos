import unittest
import tempfile
import shutil
from pathlib import Path

# import module using regular package import
from tools import auto_fix_dts as af


class TestAutoFixDts(unittest.TestCase):
    def run_helper_with_file(self, content: str, apply: bool = True):
        td = tempfile.mkdtemp()
        try:
            tdpath = Path(td)
            fpath = tdpath / 'test-overlay.dts'
            fpath.write_text(content)
            report = tdpath / 'report.txt'
            changed, summary = af.process_file(str(fpath), apply=apply, backup=True, report=str(report), verbose=False, dtc_inc=None)
            return fpath, report, changed, summary, td
        except Exception:
            shutil.rmtree(td)
            raise

    def test_add_reg_for_unit_node_no_reg(self):
        content = """/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2835";
    fragment@0 {
        target-path = "/";
        __overlay__  {
            battery: battery@0 {
                compatible = "simple-battery";
            };
        };
    };
};
"""
        fpath, report, changed, summary, td = self.run_helper_with_file(content, apply=True)
        try:
            self.assertTrue(changed)
            txt = fpath.read_text()
            # reg should have been added and a backup created; allow for either <0> or <0 0> etc
            self.assertRegex(txt, r'reg\s*=\s*<\s*0(?:\s+0)*\s*>;')
            self.assertTrue((fpath.with_suffix('.dts.orig')).exists())
        finally:
            shutil.rmtree(td)

    def test_pad_reg_for_parent_address_cells(self):
        content = """/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2835";
    fragment@0 {
        target-path = "/";
        __overlay__  {
            #address-cells = <2>;
            spidev4_0: spidev@0 {
                reg = <0>;
                compatible = "spidev";
            };
        };
    };
};
"""
        fpath, report, changed, summary, td = self.run_helper_with_file(content, apply=True)
        try:
            self.assertTrue(changed)
            txt = fpath.read_text()
            self.assertIn('reg = <0 0>;', txt)
        finally:
            shutil.rmtree(td)

    def test_do_not_modify_fragment_nodes(self):
        content = """/dts-v1/;
/plugin/;

/ {
    compatible = "brcm,bcm2835";
    fragment@0 {
        target-path = "/";
        __overlay__  {
            /* a fragment node should remain a fragment */
            some: fragment@0 {
                compatible = "foo";
            };
        };
    };
};
"""
        fpath, report, changed, summary, td = self.run_helper_with_file(content, apply=True)
        try:
            self.assertFalse('reg = <0>;' in fpath.read_text())
        finally:
            shutil.rmtree(td)

    def test_no_apply_creates_fixed(self):
        content = """/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target-path = "/";
        __overlay__  {
            battery: battery@0 {
                compatible = "simple-battery";
            };
        };
    };
};
"""
        fpath, report, changed, summary, td = self.run_helper_with_file(content, apply=False)
        try:
            self.assertTrue(changed)
            fixed_path = fpath.with_suffix('.fixed.dts')
            self.assertTrue(fixed_path.exists(), 'fixed file should be produced when apply=False')
            # original unchanged
            self.assertFalse('reg = <0>;' in fpath.read_text())
        finally:
            shutil.rmtree(td)


if __name__ == '__main__':
    unittest.main()
