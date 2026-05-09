import ezdxf

def dump_text(path):
    try:
        doc = ezdxf.readfile(path)
        msp = doc.modelspace()
        print(f"--- TEXT DUMP FOR {path} ---")
        for e in msp.query('TEXT MTEXT'):
            txt = (e.dxf.text if e.dxftype() == 'TEXT' else e.text)
            print(f"[{e.dxftype()}] {txt}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    dump_text(r"C:\Users\sukhs\OneDrive\Documents\8th_Sem_Project\house.dxf")
