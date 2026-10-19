// SearchFold.fold from ios/RailKit/Sources/RailCore/Utilities/SearchFold.swift.
// The explicit variant table is the same map. General Hant-Hans (CFStringTransform)
// is not available in Node; characters outside this table stay as written.
// Identity matching is exact folded equality, so an unconverted pair fails closed.

const VARIANTS = {
  鉄: "铁", 鐵: "铁", 営: "营", 広: "广", 浜: "滨", 沢: "泽",
  関: "关", 県: "县", 気: "气", 発: "发", 図: "图", 線: "线",
  東: "东", 電: "电", 車: "车", 臺: "台", 桜: "樱", 竜: "龙",
  戸: "户", 楽: "乐", 渋: "涩", 円: "圆", 黒: "黑", 徳: "德",
  歩: "步", 経: "经", 塩: "盐", 辺: "边", 恵: "惠", 横: "横",
  浅: "浅", 駒: "驹", 舘: "馆", 館: "馆", 庁: "厅", 区: "区",
  蔵: "藏", ヶ: "ケ", ヵ: "ケ",
};

function isLatinBase(codePoint) {
  return (codePoint >= 0x41 && codePoint <= 0x7a) || (codePoint >= 0xc0 && codePoint <= 0x024f);
}

function stripLatinDiacritic(character) {
  const decomposed = character.normalize("NFD");
  const first = decomposed.codePointAt(0);
  if (!isLatinBase(first)) return character;
  return decomposed.replace(/\p{M}/gu, "");
}

function hiraganaToKatakana(character) {
  const code = character.codePointAt(0);
  if ((code >= 0x3041 && code <= 0x3096) || (code >= 0x309d && code <= 0x309e)) {
    return String.fromCodePoint(code + 0x60);
  }
  return character;
}

function isIgnored(character) {
  return /[\p{White_Space}\p{P}\p{S}]/u.test(character);
}

function isDigit(character) {
  return /\p{Nd}/u.test(character);
}

export function searchFold(value) {
  let text = String(value ?? "").normalize("NFKC").toLowerCase();
  text = Array.from(text, stripLatinDiacritic).join("");
  text = Array.from(text, hiraganaToKatakana).join("");
  text = Array.from(text, (character) => VARIANTS[character] ?? character).join("");
  let kept = "";
  let separated = false;
  for (const character of text) {
    if (isIgnored(character)) {
      separated = true;
      continue;
    }
    if (separated && kept && isDigit(kept[kept.length - 1]) && isDigit(character)) kept += " ";
    kept += character;
    separated = false;
  }
  return kept;
}
