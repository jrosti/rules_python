import sys
import site

# Call site.addsitedir() for all PYTHONPATH entries inside runfiles.
# This causes any .pth files to be processed.  Without this, .pth files are not processed
# and some namespace packages (like google.*) will not work.
for p in list(sys.path):
    if ".runfiles/" in p:
        site.addsitedir(p)
