# Generates the toddler illustrations in HelloFlight/Illustrations with the OpenAI Images API.
# Usage: OPENAI_API_KEY=... python3 ci/generate-illustrations.py HelloFlight/Illustrations [key ...]
# Existing files are kept; delete one to regenerate it.
import base64, io, json, os, sys, concurrent.futures, urllib.request
from PIL import Image
OUT = sys.argv[1]
SUBJECTS = {
 "ant":"ant","strawberry":"strawberry","rabbit":"white rabbit","shrimp":"shrimp","riceball":"Japanese onigiri rice ball with nori",
 "crab":"red crab","giraffe":"giraffe","bear":"brown bear","cake":"strawberry shortcake slice","koala":"koala","monkey":"monkey",
 "deer":"deer","watermelon":"watermelon slice","octopus":"red octopus","butterfly":"butterfly","moon":"crescent moon",
 "hand":"open hand waving","tomato":"tomato","eggplant":"eggplant","carrot":"carrot","cat":"cat","tulip":"red tulip flower",
 "chick":"yellow baby chick","boat":"sailboat","snake":"green snake","star":"yellow star","orange":"orange fruit",
 "caterpillar":"green caterpillar","glasses":"eyeglasses","peach":"peach","mountain":"mountain with snowy peak",
 "snowman":"snowman","lion":"lion","apple":"red apple","lemon":"lemon","rocket":"rocket","crocodile":"crocodile",
 "icecream":"ice cream cone","dolphin":"dolphin","horse":"horse","ghost":"friendly cute ghost","turtle":"turtle",
 "kiwi":"kiwi fruit cut in half","whale":"blue whale","zebra":"zebra","tv":"retro television","bee":"honey bee",
 "melon":"cantaloupe melon","goat":"goat","dog":"puppy dog","egg":"white egg","fish":"blue fish","grapes":"bunch of purple grapes",
 "hat":"top hat","juice":"juice box with straw","kite":"diamond kite with tail","nose":"cartoon nose","penguin":"penguin",
 "queen":"queen with crown", "unicorn":"white baby unicorn with pastel rainbow mane and golden horn","sun":"smiling sun","tiger":"tiger","umbrella":"umbrella","violin":"violin","yoyo":"yo-yo toy",
 "finger":"hand pointing up with the index finger extended, other fingers folded, light skin, white cartoon glove-like cuff",
 "slide":"playground slide with a light blue chute, a small ladder and snowy top, side view",
}
STYLE = ("A single cute {s}, children's picture-book sticker illustration for toddlers, simple rounded shapes, "
         "bold dark navy outline, bright saturated flat colors with soft shading, centered, filling most of the frame, "
         "no text, no letters, no background, transparent background.")
# The title logo (wide, shown without a card on the title screen).
LOGO = ("A playful title logo for a toddler game, the Japanese words \"ペンギン すべりだい\" written exactly in that katakana and hiragana, "
        "in two lines: \"ペンギン\" on top and \"すべりだい\" below, chunky rounded bubbly letters, icy light blue and white letters with "
        "a thick dark navy outline and a soft white inner highlight, a few snowflakes and a tiny cute penguin peeking from the side, "
        "clean sticker style, transparent background, no other text.")
def gen(key):
    path = os.path.join(OUT, key + ".png")
    if os.path.exists(path): return key, "skip"
    logo = key == "title"
    body = json.dumps({"model":"gpt-image-1","prompt":LOGO if logo else STYLE.format(s=SUBJECTS[key]),"size":"1536x1024" if logo else "1024x1024",
                       "quality":"high" if logo else "medium","background":"transparent","output_format":"png","n":1}).encode()
    req = urllib.request.Request("https://api.openai.com/v1/images/generations", data=body,
        headers={"Authorization":"Bearer "+os.environ["OPENAI_API_KEY"],"Content-Type":"application/json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                data = json.load(r)
            img = Image.open(io.BytesIO(base64.b64decode(data["data"][0]["b64_json"]))).convert("RGBA")
            bbox = img.getbbox() or (0,0,1024,1024)
            img = img.crop(bbox)
            if logo:
                img.thumbnail((900, 600), Image.LANCZOS)
                img.save(path, optimize=True)
                return key, "ok"
            side = max(img.size); canvas = Image.new("RGBA",(side,side),(0,0,0,0))
            canvas.paste(img,((side-img.size[0])//2,(side-img.size[1])//2))
            canvas.resize((256,256), Image.LANCZOS).quantize(colors=128, method=Image.FASTOCTREE).save(path, optimize=True)
            return key, "ok"
        except Exception as e:
            err = e
            if hasattr(e, "read"): err = e.read()[:300]
    return key, f"fail {err}"
keys = sys.argv[2:] or list(SUBJECTS) + ["title"]
with concurrent.futures.ThreadPoolExecutor(6) as ex:
    for k, s in ex.map(gen, keys): print(k, s, flush=True)
