import os
import re
import shutil
import tempfile
import unittest
from glob import glob
from collections import defaultdict

import numpy as np
import torch
from torchvision.io import read_image

from flat_bug import logger
from flat_bug.predictor import Predictor, TensorPredictions
from flat_bug.tests.remote_lfs_fallback import check_file_with_remote_fallback

TEST_MODEL_NAME = "flat_bug_M.pt"
PYRAMID_SCALE_BEFORE = 0.6
ASSET_DIR = os.path.join(os.path.dirname(__file__), "assets")
ASSET_NAME = "ALUS_Non-miteArachnids_Unknown_2020_11_03_4545"
ASSET_DIR = os.path.join(os.path.dirname(__file__), "assets")
UUID = "XXXX"
SERIALISED_TENSOR_PREDS = os.path.join(ASSET_DIR, f"metadata_{ASSET_NAME}_UUID_{UUID}.json")
N_PREDICTIONS = {
    "XXXX" : 11,
    "ChangeThisTEMPORARY" : 10
}
N_PREDICTIONS = N_PREDICTIONS.get(UUID, None)
if N_PREDICTIONS is None:
    raise ValueError(f"Number of predictions for UUID {UUID} is not known")

TEST_CFG = {
    "SCORE_THRESHOLD": 0.2,
    "IOU_THRESHOLD": 0.25,
    "MINIMUM_TILE_OVERLAP": 384,
    "EDGE_CASE_MARGIN": 64,
    "MIN_MAX_OBJ_SIZE": (16, 10**8),
    "MAX_MASK_SIZE": 1024,
    "PREFER_POLYGONS": True,
    "EXPERIMENTAL_NMS_OPTIMIZATION": True,
    "TIME": False,
    "TILE_SIZE": 1024,
    "BATCH_SIZE": 1
}

class TestTensorPredictions(unittest.TestCase):
    def test_load(self):
        tp = TensorPredictions()
        tp.load(check_file_with_remote_fallback(SERIALISED_TENSOR_PREDS))
        self.assertEqual(len(tp), N_PREDICTIONS, msg=f"Number of predictions ({len(tp)}) does not match the expected number of predictions ({N_PREDICTIONS})")

    def test_save(self):
        tp = TensorPredictions()
        tp = tp.load(check_file_with_remote_fallback(SERIALISED_TENSOR_PREDS))
        image_path = os.path.join(os.path.dirname(__file__), "assets", f"{ASSET_NAME}.jpg")
        check_file_with_remote_fallback(image_path)
        tp.image = read_image(image_path) * 255
        with tempfile.TemporaryDirectory() as tmp_directory:
            save_dir = tp.save(tmp_directory, mask_crops=True)
            self.assertTrue(os.path.exists(os.path.join(save_dir, "crops")))
            crops = glob(os.path.join(save_dir, "crops", "*"))
            n_crops = len(crops)
            # ###### DEBUG ######
            # [shutil.move(c, os.path.join(os.path.dirname(__file__), "assets", os.path.basename(c))) for c in crops]
            # overview = glob(os.path.join(save_dir, "overview*"))[0] 
            # shutil.move(overview, os.path.join(os.path.dirname(__file__), "assets", os.path.basename(overview)))
            # ###################
            self.assertEqual(n_crops, N_PREDICTIONS, msg=f"Number of crops ({n_crops}) saved does not match the expected number of predictions ({N_PREDICTIONS})")
            centroid_initial = [i.float().mean(dim=0).numpy() for i in tp.contours]
            centroid_reloaded = [i.float().mean(dim=0).numpy() for i in TensorPredictions().load(glob(os.path.join(save_dir, "metadata*.json"))[0]).contours]
            centroid_initial = np.stack(centroid_initial)
            centroid_reloaded = np.stack(centroid_reloaded)
            abs_diff = np.abs(centroid_initial - centroid_reloaded).max()
            self.assertTrue(abs_diff < 0.01, msg=f"Centroid difference between initial and reloaded contours ({abs_diff}) is too large")

def cast_nested(obj, new_dtype):
    if not isinstance(obj, torch.Tensor):
        if hasattr(obj, "__iter__"):
            return [cast_nested(o, new_dtype) for o in obj]
        return obj
    return obj.to(new_dtype)

class DummyModel(torch.nn.Module):
    def __init__(self, type : str, asset_dir : str):
        if type not in ["single_scale", "pyramid"]:
            raise ValueError(f"Invalid type {type}")
        self.type = type
        self.asset_dir = asset_dir
        self.index = 1

        self.save_counter = defaultdict(lambda : 0)

    def to(self, *args, **kwargs):
        return self

    def cpu(self):
        return self

    def cuda(self, *args, **kwargs):
        return self
    
    def eval(self):
        return self

    def train(self, mode=True):
        return self

    def __call__(self, image):
        try:
            this_asset = os.path.join(self.asset_dir, f'{self.type}_tps_{self.index}.pt')
            print(f'Processing asset {this_asset}')
            check_file_with_remote_fallback(this_asset)
            out = cast_nested(torch.load(this_asset, map_location=image.device), image.dtype)
        except Exception as e:
            logger.error(
                f'Failed to load test file "{self.type}_tps_{self.index}.pt" - '
                'consider generating the test files with '
                '`python3 src/flat_bug/tests/generate_model_outputs.py '
                '--model model_snapshots/fb_2024-03-18_large_best.pt '
                '--image src/flat_bug/tests/assets/ALUS_Non-miteArachnids_Unknown_2020_11_03_4545.jpg '
                '--type both`'
            )
            raise e
        self.index += 1
        return out
    
    def hook_save_raw_output(self, model, label : str):
        ocall = model.__call__

        def call_wrapped(*args, **kwargs):
            output = ocall(*args, **kwargs)
            self.save_counter[label] += 1
            torch.save(cast_nested(output, torch.device("cpu")), os.path.join(self.asset_dir, f'tps_{self.save_counter[label]}.pt'))
            return output
        
        model.__call__ = call_wrapped

    def generate_single_scale_files(self, weights, image):
        dtype, device = image.dtype, image.device
        model = Predictor(model=weights, device=device, dtype=dtype, cfg=TEST_CFG)
        self.hook_save_raw_output(model._model, "single_scale")
        model.TIME = True
        model.total_detection_time = 0
        model.total_forward_time = 0
        output = model._detect_instances(image, scale=(model.TILE_SIZE / torch.tensor(image.shape[1:])).min().item(), max_scale=False)
        # Rename the files with the pattern "assets/tps_<NUMBER>.pt" to "assets/single_scale_tps_<NUMBER>.pt"
        [shutil.move(f, os.path.join(self.asset_dir, re.sub(r'tps_', "single_scale_tps_", f))) for f in glob(os.path.join(self.asset_dir, "tps_*.pt"))]
        # Create a file with the length of the output object as a reference - this is the number of detections in the final object
        with open(os.path.join(self.asset_dir, "single_scale_output_length.txt"), "w") as f:
            f.write(str(len(output)))

    def generate_pyramid_files(self, weights, image, image_path):
        dtype, device = image.dtype, image.device
        model = Predictor(model=weights, device=device, dtype=dtype, cfg=TEST_CFG)
        self.hook_save_raw_output(model._model, "pyramid")
        model.TIME = True
        output = model.pyramid_predictions(image, image_path, scale_increment=1/2, scale_before=PYRAMID_SCALE_BEFORE, single_scale=False)
        # Rename the files with the pattern "assets/tps_<NUMBER>.pt" to "assets/pyramid_tps_<NUMBER>.pt"
        [shutil.move(f, os.path.join(self.asset_dir, re.sub(r'tps_', "pyramid_tps_", f))) for f in glob(os.path.join(self.asset_dir, "tps_*.pt"))]
        # Create a file with the length of the output object as a reference - this is the number of detections in the final object
        with open(os.path.join(self.asset_dir, "pyramid_output_length.txt"), "w") as f:
            f.write(str(len(output)))

class TestPredictor(unittest.TestCase):
    TOLERANCE = 0.1

    def test_single_scale(self):
        dtype = torch.float16
        predictor = Predictor(model=DummyModel("single_scale", ASSET_DIR), dtype=dtype, cfg=TEST_CFG)
        image_path = os.path.join(ASSET_DIR, ASSET_NAME + ".jpg")
        check_file_with_remote_fallback(image_path)
        image = read_image(image_path).to(torch.device("cpu"), dtype=dtype) / 255.
        output = predictor._detect_instances(image, scale=(predictor.TILE_SIZE / torch.tensor(image.shape[1:])).min().item(), max_scale=False)
        output_length = len(output)
        with open(check_file_with_remote_fallback(os.path.join(ASSET_DIR, "single_scale_output_length.txt"))) as f:
            reference_length = int(f.read())
        # Check that the output length is within tolerance of the reference length
        self.assertTrue(abs(1 - output_length/reference_length) < self.TOLERANCE, msg=f"Output length ({output_length}) does not match the reference length ({reference_length})")
    
    def test_pyramid(self):
        dtype = torch.float16
        predictor = Predictor(model=DummyModel("pyramid", ASSET_DIR), dtype=dtype, cfg=TEST_CFG)
        image_path = os.path.join(ASSET_DIR, ASSET_NAME + ".jpg")
        check_file_with_remote_fallback(image_path)
        image = read_image(image_path).to(torch.device("cpu"), dtype=dtype) / 255.
        output = predictor.pyramid_predictions(image, image_path, scale_increment=1/2, scale_before=PYRAMID_SCALE_BEFORE, single_scale=False)
        output_length = len(output)
        with open(check_file_with_remote_fallback(os.path.join(ASSET_DIR, "pyramid_output_length.txt"))) as f:
            reference_length = int(f.read())
        # Check that the output length is within tolerance of the reference length
        self.assertTrue(abs(1 - output_length/reference_length) < self.TOLERANCE, msg=f"Output length ({output_length}) does not match the reference length ({reference_length})")

if __name__ == '__main__':
    unittest.main()