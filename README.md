## How to build

Instructions for macOS. Adapt for your OS if different.

Replace `path-to` by your own directory paths.

1. Install **python 3**: `brew install python3`
2. Clone `forgepush` from https://github.com/tmg-pub/forgepush
3. Switch to the cloned forgepush directory: `cd path-to/forgepush`
4. Create virtual environement for *forgepush*: `python3 -m venv venv`
5. Install python 3 modules: `venv/bin/pip install pyyaml requests`
6. Go to the addon repo folder: `cd path-to/crossrp`
7. Build the addon: `path-to/forgepush/venv/bin/python3 path-to/forgepush/forgepush.py --publish_curseforge --curse_apitoken null`

	The built addon is under the `path-to/crossrp/.forgepush/CrossRP` folder.

8. Create symlink to the built addon
	```bash
	cd path-to/World\ of\ Warcraft/_retail_/Interface/AddOns/CrossRP
	ln -s path-to/crossrp/.forgepush/CrossRP CrossRP
	````

To build the addon again, just repeat steps 6 and 7.