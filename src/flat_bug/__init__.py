import logging
import urllib.error
import urllib.parse
import urllib.request
from typing import Optional

from tqdm import tqdm

REMOTE_REPOSITORY = "https://anon.erda.au.dk/share_redirect/Bb0CR1FHG6/"

# Thanks to: https://stackoverflow.com/a/53877507/19104786
class DownloadProgressBar(tqdm):
    def update_to(self, b : int=1, bsize : int=1, tsize : Optional[int]=None):
        if tsize is not None:
            self.total = tsize
        self.update(b * bsize - self.n)

def download_from_repository(url : str, output_path : Optional[str]=None, strict : bool=True, progress : bool=True):
    if output_path is None:
        output_path = url
    url = urllib.parse.quote(urllib.parse.urljoin(REMOTE_REPOSITORY, url), safe="/:")
    try:
        if progress:
            with DownloadProgressBar(unit='B', unit_scale=True, miniters=1, desc=f'Downloading {url} to {output_path}') as t:
                urllib.request.urlretrieve(url, filename=output_path, reporthook=t.update_to)
        else:
                urllib.request.urlretrieve(url, filename=output_path)
    except Exception as e:
        if not strict:
            return False
        else:
            raise e
    return True

# TODO: Improve this perhaps using https://gist.github.com/aldur/f356f245014523330a7070ab12bcfb1f, 
# REDACTED
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', 
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)

def set_log_level(level):
    logger.setLevel(level)
    logger.info(f'Log level set to {level}')