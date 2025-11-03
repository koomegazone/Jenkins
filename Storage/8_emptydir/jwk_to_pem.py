import json
import base64
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

# JWK JSON (여기에 복사)
jwk = {
  "kty": "RSA",
  "kid": "abc52989441f740b1cda08ac374bf205d5e0b6e7",
  "use": "sig",
  "alg": "RS256",
  "n": "t5PtjDjIlTB3_YhCa9SyjKQ69cfoSPM_i9_TzPY8LXnan_nF6fg_LWCes7KujhwpoATKcjddhSq11jAFrZaJSCR1Ue1c46mFpfN3l6PXjcg-nO7_Asp7Xw5VMQ4jfNDp7Kr1y4dgsh9ECLPgKk4_dyqTshqBnBsPPl0jRUr4hUnsai--bqf6K1Ca2zPdZvzNksRuT_5F4jyaW_0QuX7-eW360M-0-HfckWxIluC_E0dxhSVBQyfQ6ekpnKwxPoyKgaVhXyBS2mrIGx_7Kpk7yFz1aJYeKLnX5JE7jVhj0iVdqOQdWQ5R93WsDs23qeFwpir_PtkHbGkJcaLcT7W5WQ",
  "e": "AQAB"
}

# base64url → int
def b64url_to_long(val):
    val += "=" * (-len(val) % 4)  # padding
    return int.from_bytes(base64.urlsafe_b64decode(val), "big")

n = b64url_to_long(jwk["n"])
e = b64url_to_long(jwk["e"])

# 공개키 객체 생성
public_key = rsa.RSAPublicNumbers(e, n).public_key()

# PEM 형식으로 저장
pem = public_key.public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo
)

with open("sa.pub", "wb") as f:
    f.write(pem)

print("✅ sa.pub 파일 생성 완료")
