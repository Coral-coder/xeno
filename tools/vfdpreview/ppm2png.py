import glob, sys
from PIL import Image
for f in sorted(glob.glob(sys.argv[1] + '/*.ppm')):
    Image.open(f).save(f[:-4] + '.png')
