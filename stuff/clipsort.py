from Tkinter import Tk
r = Tk()
r.withdraw()
r.clipboard_clear()
r.clipboard_append('i can has clipboardz?')
r.update() # now it stays on the clipboard after the window is closed
r.destroy()
