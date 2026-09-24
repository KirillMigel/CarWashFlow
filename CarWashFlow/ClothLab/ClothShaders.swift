enum ClothShaders {

    static let source = """
#include <metal_stdlib>
using namespace metal;

constant float PI = 3.141592653589793;
constant float RECIP_PI = 0.3183098861837907;

struct U {
    float4x4 model;
    float4x4 viewProj;
    float4 camera;
    float4 base;
    float4 sheenC;
    float4 tint;
    float4 pointC;
    float4 m0;
    float4 m1;
    float4 m2;
    float4 tiles;
    float4 env;
    float4 view;
    float4 grain;
    float4 bg0;
    float4 bg1;
    float4 bg2;
    float4 bgP;
    float4 bgM;
};

inline float pow2(float x) { return x * x; }
inline float3 pow2(float3 x) { return x * x; }
inline float max3(float3 v) { return max(max(v.x, v.y), v.z); }

inline float3 F_Schlick(float3 f0, float f90, float dotVH) {
    float f = pow(1.0 - dotVH, 5.0);
    return f0 * (1.0 - f) + (f90 * f);
}
inline float F_Schlick(float f0, float f90, float dotVH) {
    float f = pow(1.0 - dotVH, 5.0);
    return f0 * (1.0 - f) + (f90 * f);
}
inline float V_GGX_SmithCorrelated(float alpha, float dotNL, float dotNV) {
    float a2 = pow2(alpha);
    float gv = dotNL * sqrt(a2 + (1.0 - a2) * pow2(dotNV));
    float gl = dotNV * sqrt(a2 + (1.0 - a2) * pow2(dotNL));
    return 0.5 / max(gv + gl, 1e-6);
}
inline float D_GGX(float alpha, float dotNH) {
    float a2 = pow2(alpha);
    float d = (dotNH * a2 - dotNH) * dotNH + 1.0;
    return RECIP_PI * a2 / pow2(d);
}
inline float2 DFGApprox(float dotNV, float roughness) {
    const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
    const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
    float4 r = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * dotNV)) * r.x + r.y;
    return float2(-1.04, 1.04) * a004 + r.zw;
}
inline float D_Charlie(float roughness, float dotNH) {
    float alpha = pow2(roughness);
    float invAlpha = 1.0 / max(alpha, 1e-4);
    float cos2h = dotNH * dotNH;
    float sin2h = max(1.0 - cos2h, 0.0078125);
    return (2.0 + invAlpha) * pow(sin2h, invAlpha * 0.5) / (2.0 * PI);
}
inline float V_Neubelt(float dotNV, float dotNL) {
    return saturate(1.0 / (4.0 * (dotNL + dotNV - dotNL * dotNV)));
}
inline float3 BRDF_Sheen(float3 n, float3 v, float3 l, float3 sheenColor, float sheenRoughness) {
    float3 h = normalize(l + v);
    float dotNL = saturate(dot(n, l));
    float dotNV = saturate(dot(n, v));
    float dotNH = saturate(dot(n, h));
    return sheenColor * (D_Charlie(sheenRoughness, dotNH) * V_Neubelt(dotNV, dotNL));
}
inline float IBLSheenBRDF(float dotNV, float roughness) {
    float r2 = roughness * roughness;
    float a = roughness < 0.25 ? -339.2 * r2 + 474.7 * roughness - 163.7
                               : -8.48 * r2 + 14.3 * roughness - 9.95;
    float b = roughness < 0.25 ? 44.0 * r2 - 61.5 * roughness + 24.2
                               : 1.97 * r2 - 3.27 * roughness + 0.72;
    return saturate(exp(a * dotNV + b) * RECIP_PI);
}

inline float3 Fresnel0ToIor(float3 f0) {
    float3 s = sqrt(f0);
    return (1.0 + s) / max(1.0 - s, 1e-4);
}
inline float3 IorToFresnel0(float3 transmitted, float incident) {
    return pow2((transmitted - incident) / (transmitted + incident));
}
inline float IorToFresnel0(float transmitted, float incident) {
    return pow2((transmitted - incident) / (transmitted + incident));
}
inline float3 evalSensitivity(float opd, float3 shift) {
    float phase = 2.0 * PI * opd * 1.0e-9;
    const float3 val = float3(5.4856e-13, 4.4201e-13, 5.2481e-13);
    const float3 pos = float3(1.6810e+06, 1.7953e+06, 2.2084e+06);
    const float3 var_ = float3(4.3278e+09, 9.3046e+09, 6.6121e+09);
    float3 xyz = val * sqrt(2.0 * PI * var_) * cos(pos * phase + shift) * exp(-pow2(phase) * var_);
    xyz.x += 9.7470e-14 * sqrt(2.0 * PI * 4.5282e+09)
           * cos(2.2399e+06 * phase + shift.x) * exp(-4.5282e+09 * pow2(phase));
    xyz /= 1.0685e-7;
    const float3x3 XYZ_TO_REC709 = float3x3(float3( 3.2404542, -0.9692660,  0.0556434),
                                            float3(-1.5371385,  1.8760108, -0.2040259),
                                            float3(-0.4985314,  0.0415560,  1.0572252));
    return XYZ_TO_REC709 * xyz;
}
inline float3 evalIridescence(float outsideIOR, float eta2, float cosTheta1,
                              float thickness, float3 baseF0) {
    float iridescenceIOR = mix(outsideIOR, eta2, smoothstep(0.0, 0.03, thickness));
    float sinTheta2Sq = pow2(outsideIOR / iridescenceIOR) * (1.0 - pow2(cosTheta1));
    float cosTheta2Sq = 1.0 - sinTheta2Sq;
    if (cosTheta2Sq < 0.0) return float3(1.0);
    float cosTheta2 = sqrt(cosTheta2Sq);

    float R0 = IorToFresnel0(iridescenceIOR, outsideIOR);
    float R12 = F_Schlick(R0, 1.0, cosTheta1);
    float T121 = 1.0 - R12;
    float phi12 = iridescenceIOR < outsideIOR ? PI : 0.0;
    float phi21 = PI - phi12;

    float3 baseIOR = Fresnel0ToIor(clamp(baseF0, 0.0, 0.9999));
    float3 R1 = IorToFresnel0(baseIOR, iridescenceIOR);
    float3 R23 = F_Schlick(R1, 1.0, cosTheta2);
    float3 phi23 = float3(baseIOR.x < iridescenceIOR ? PI : 0.0,
                          baseIOR.y < iridescenceIOR ? PI : 0.0,
                          baseIOR.z < iridescenceIOR ? PI : 0.0);

    float opd = 2.0 * iridescenceIOR * thickness * cosTheta2;
    float3 phi = float3(phi21) + phi23;

    float3 R123 = clamp(R12 * R23, 1e-5, 0.9999);
    float3 r123 = sqrt(R123);
    float3 Rs = pow2(T121) * R23 / (float3(1.0) - R123);

    float3 I = R12 + Rs;
    float3 Cm = Rs - T121;
    for (int m = 1; m <= 2; ++m) {
        Cm *= r123;
        float3 Sm = 2.0 * evalSensitivity(float(m) * opd, float(m) * phi);
        I += Cm * Sm;
    }
    return max(I, float3(0.0));
}
inline float3 Schlick_to_F0(float3 f, float f90, float dotVH) {
    float x = clamp(1.0 - dotVH, 0.0, 1.0);
    float x5 = clamp(x * x * x * x * x, 0.0, 0.9999);
    return (f - float3(f90) * x5) / (1.0 - x5);
}

inline float3 softPanel(float3 d, float3 axis, float rough) {
    float sharp = mix(26.0, 1.2, saturate(rough * 1.4 + 0.06));
    float norm = (sharp + 1.0) / 27.0;
    return float3(norm * pow(saturate(dot(d, axis)), sharp));
}
inline float3 roomEnv(float3 d, float rough) {
    float up = d.y;
    float3 c = mix(float3(0.05, 0.053, 0.062), float3(0.55, 0.57, 0.62),
                   smoothstep(-1.0, -0.02, up));
    c = mix(c, float3(2.00, 2.05, 2.15), smoothstep(0.10, 0.80, up));
    c += 1.70 * softPanel(d, normalize(float3(0.42, 0.62, 0.66)), rough);
    c += 0.55 * float3(0.82, 0.86, 0.95) * softPanel(d, normalize(float3(0.10, 0.05, 1.0)), rough);
    c += 0.30 * float3(0.78, 0.84, 0.95) * softPanel(d, normalize(float3(-0.85, -0.18, 0.5)), rough);
    c += 0.70 * softPanel(d, normalize(float3(-0.32, 0.42, -0.85)), rough);
    return c;
}

inline float3 acesFilmic(float3 color, float exposure) {
    const float3x3 IN = float3x3(float3(0.59719, 0.07600, 0.02840),
                                 float3(0.35458, 0.90834, 0.13383),
                                 float3(0.04823, 0.01566, 0.83777));
    const float3x3 OUT = float3x3(float3( 1.60475, -0.10208, -0.00327),
                                  float3(-0.53108,  1.10813, -0.07276),
                                  float3(-0.07367, -0.00605,  1.07602));
    color *= exposure / 0.6;
    color = IN * color;
    float3 a = color * (color + 0.0245786) - 0.000090537;
    float3 b = color * (0.983729 * color + 0.4329510) + 0.238081;
    color = a / b;
    color = OUT * color;
    return saturate(color);
}
inline float3 linearToSRGB(float3 c) {
    return mix(c * 12.92, 1.055 * pow(max(c, 1e-5), 1.0 / 2.4) - 0.055, step(0.0031308, c));
}

struct SurfaceOut {
    float4 position [[position]];
    float3 worldPos;
    float3 worldNormal;
    float2 uv;
};

struct PointOut {
    float4 position [[position]];
    float  size [[point_size]];
    float2 uv;
    float3 worldNormal;
};

struct FullOut {
    float4 position [[position]];
    float2 ndc;
};

vertex SurfaceOut cloth_surface_vertex(uint vid [[vertex_id]],
                                       constant U &u [[buffer(0)]],
                                       const device packed_float3 *positions [[buffer(1)]],
                                       const device packed_float3 *normals [[buffer(2)]],
                                       const device packed_float2 *uvs [[buffer(3)]]) {
    float3 local = float3(positions[vid]);
    float3 n = float3(normals[vid]);
    float4 world = u.model * float4(local, 1.0);
    SurfaceOut o;
    o.position = u.viewProj * world;
    o.worldPos = world.xyz;
    o.worldNormal = (u.model * float4(n, 0.0)).xyz;
    o.uv = float2(uvs[vid]);
    return o;
}

vertex PointOut cloth_points_vertex(uint vid [[vertex_id]],
                                     constant U &u [[buffer(0)]],
                                     const device packed_float3 *positions [[buffer(1)]],
                                     const device packed_float3 *normals [[buffer(2)]],
                                     const device packed_float2 *uvs [[buffer(3)]]) {
    float3 local = float3(positions[vid]);
    float4 world = u.model * float4(local, 1.0);
    float4 clip = u.viewProj * world;
    PointOut o;
    o.position = clip;
    float viewZ = max(clip.w, 1e-3);
    o.size = u.grain.w > 0.0 ? u.grain.w : max(1.0, u.env.w * 0.5 * u.view.y / viewZ);
    o.uv = float2(uvs[vid]);
    o.worldNormal = (u.model * float4(float3(normals[vid]), 0.0)).xyz;
    return o;
}

vertex FullOut cloth_fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullOut o;
    o.ndc = p * 2.0 - 1.0;
    o.position = float4(o.ndc, 0.0, 1.0);
    return o;
}

fragment float4 cloth_background_fragment(FullOut in [[stage_in]],
                                           constant U &u [[buffer(0)]]) {
    float mode = u.bgM.x;
    if (mode < 0.5) return float4(0.0);
    float2 uv = float2(in.ndc.x * 0.5 + 0.5, 0.5 - in.ndc.y * 0.5);
    if (mode < 1.5) return float4(u.bg0.rgb, 1.0);
    float2 c = u.bgP.xy;
    float aspect = max(u.bgM.y, 1e-4);
    float2 radius = aspect >= 1.0 ? float2(u.bgP.z / aspect, u.bgP.w)
                                  : float2(u.bgP.z, u.bgP.w * aspect);
    float2 d = (uv - c) / max(radius, float2(1e-4));
    float t = saturate(length(d));
    float3 col = t < 0.55 ? mix(u.bg0.rgb, u.bg1.rgb, t / 0.55)
                          : mix(u.bg1.rgb, u.bg2.rgb, (t - 0.55) / 0.45);
    return float4(col, 1.0);
}

fragment float4 cloth_surface_fragment(SurfaceOut in [[stage_in]],
                                        constant U &u [[buffer(0)]],
                                        texture2d<float> fillTex [[texture(0)]],
                                        texture2d<float> weaveTex [[texture(1)]],
                                        sampler fillSmp [[sampler(0)]],
                                        sampler weaveSmp [[sampler(1)]],
                                        bool frontFacing [[front_facing]]) {

    float3 viewDir = normalize(u.camera.xyz - in.worldPos);
    float3 geoNormal = normalize(in.worldNormal) * (frontFacing ? 1.0 : -1.0);

    float3 albedo = u.base.rgb;
    float3 emissive = float3(0.0);
    float surfaceAlpha = 1.0;
    float roughness = u.base.w;
    float metalness = u.m0.x;
    float sheenAmount = u.sheenC.w;
    float envIntensity = u.m0.z;
    float bumpScale = u.m0.w;

    if (u.m2.y > 0.5) {
        float2 fuv = in.uv * u.tiles.zw;
        float4 texel = fillTex.sample(fillSmp, fuv);
        surfaceAlpha = texel.a;
        if (surfaceAlpha <= 0.002) discard_fragment();
        float3 picture = texel.rgb * u.tint.rgb;
        albedo = mix(u.base.rgb, picture, texel.a);
        if (u.m2.z > 0.5) emissive = picture * texel.a * u.tint.w;
    }

    float3 normal = geoNormal;
    if (u.m2.x > 0.5 && bumpScale != 0.0) {
        float2 buv = in.uv * u.tiles.xy;
        float2 texel = 1.0 / float2(weaveTex.get_width(0), weaveTex.get_height(0));
        float h0 = weaveTex.sample(weaveSmp, buv).r;
        float hu = weaveTex.sample(weaveSmp, buv + float2(texel.x, 0.0)).r;
        float hv = weaveTex.sample(weaveSmp, buv + float2(0.0, texel.y)).r;
        float2 dH = float2(hu - h0, hv - h0) * bumpScale * 4.0;
        float3 dp1 = dfdx(in.worldPos), dp2 = dfdy(in.worldPos);
        float2 duv1 = dfdx(buv), duv2 = dfdy(buv);
        float3 dp2perp = cross(dp2, geoNormal);
        float3 dp1perp = cross(geoNormal, dp1);
        float3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
        float3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;
        float invmax = rsqrt(max(max(dot(tangent, tangent), dot(bitangent, bitangent)), 1e-12));
        normal = normalize(geoNormal - (tangent * dH.x + bitangent * dH.y) * invmax);
    }

    if (u.m2.w < 0.5 && u.env.x < 0.5) {
        float shade = 0.25 + 0.75 * saturate(dot(normal, viewDir));
        if (u.m2.y > 0.5) shade = mix(shade, 1.0, saturate(u.tint.w));
        return float4(linearToSRGB(saturate(albedo * (shade * u.camera.w))), surfaceAlpha);
    }

    float3 dxy = max(abs(dfdx(geoNormal)), abs(dfdy(geoNormal)));
    roughness = min(max(roughness, 0.0525) + max(max(dxy.x, dxy.y), dxy.z), 1.0);
    float alpha = pow2(roughness);

    float3 diffuseColor = albedo * (1.0 - metalness);
    float3 specularColor = mix(float3(0.04), albedo, metalness);
    float specularF90 = 1.0;

    float dotNV = saturate(dot(normal, viewDir));

    float iridescence = u.m1.x;
    float3 iridescenceFresnel = float3(0.0);
    float3 iridescenceF0 = specularColor;
    if (iridescence > 0.0) {
        float thickness = u.m1.w;
        iridescenceFresnel = evalIridescence(1.0, u.m1.y, dotNV, thickness, specularColor);
        iridescenceF0 = Schlick_to_F0(iridescenceFresnel, 1.0, dotNV);
    }

    float3 directDiffuse = float3(0.0);
    float3 directSpecular = float3(0.0);
    float3 sheenDirect = float3(0.0);
    float3 indirectDiffuse = float3(0.0);
    float3 indirectSpecular = float3(0.0);
    float3 sheenIndirect = float3(0.0);
    float3 sheenColor = u.sheenC.rgb;
    float sheenRoughness = max(u.m0.y, 0.07);

    if (u.m2.w > 0.5) {
        const float3 LDIR[3] = { normalize(float3( 2.4,  3.2,  4.5)),
                                 normalize(float3(-3.5, -1.5,  2.5)),
                                 normalize(float3(-1.5,  2.0, -4.0)) };
        const float3 LCOL[3] = { float3(2.1, 2.1, 2.1),
                                 float3(0.5085, 0.5820, 0.6841),
                                 float3(1.5, 1.5, 1.5) };
        for (int i = 0; i < 3; ++i) {
            float3 l = LDIR[i];
            float dotNL = saturate(dot(normal, l));
            if (dotNL <= 0.0) continue;
            float3 irradiance = dotNL * LCOL[i];
            float3 h = normalize(l + viewDir);
            float dotNH = saturate(dot(normal, h));
            float dotVH = saturate(dot(viewDir, h));
            float3 F = F_Schlick(specularColor, specularF90, dotVH);
            if (iridescence > 0.0) F = mix(F, iridescenceFresnel, iridescence);
            float V = V_GGX_SmithCorrelated(alpha, dotNL, dotNV);
            float D = D_GGX(alpha, dotNH);
            directSpecular += irradiance * (F * (V * D));
            directDiffuse += irradiance * (RECIP_PI * diffuseColor);
            if (sheenAmount > 0.0) {
                sheenDirect += irradiance * BRDF_Sheen(normal, viewDir, l, sheenColor, sheenRoughness);
            }
        }
        const float3 AMBIENT = float3(0.18);
        indirectDiffuse += AMBIENT * (RECIP_PI * diffuseColor);
    }

    if (u.env.x > 0.5 && envIntensity > 0.0) {
        float3 irradiance = roomEnv(normal, 1.0) * envIntensity;
        float3 reflectVec = normalize(mix(reflect(-viewDir, normal), normal, alpha));
        float3 radiance = roomEnv(reflectVec, max(roughness, u.env.y)) * envIntensity;

        float2 fab = DFGApprox(dotNV, roughness);
        float3 Fr = iridescence > 0.0 ? mix(specularColor, iridescenceF0, iridescence) : specularColor;
        float3 FssEss = Fr * fab.x + specularF90 * fab.y;
        float Ess = fab.x + fab.y;
        float Ems = 1.0 - Ess;
        float3 Favg = Fr + (1.0 - Fr) * 0.047619;
        float3 Fms = FssEss * Favg / (1.0 - Ems * Favg);
        float3 total = FssEss + Fms * Ems;
        float3 diffuseScatter = diffuseColor * (1.0 - max3(total));

        indirectSpecular += radiance * FssEss;
        indirectSpecular += (Fms * Ems) * irradiance;
        indirectDiffuse += diffuseScatter * irradiance;

        if (sheenAmount > 0.0) {
            sheenIndirect += irradiance * sheenColor * IBLSheenBRDF(dotNV, sheenRoughness);
        }
    }

    float3 outgoing = directDiffuse + indirectDiffuse + directSpecular + indirectSpecular + emissive;
    if (sheenAmount > 0.0) {
        float energy = 1.0 - 0.157 * max3(sheenColor);
        outgoing = outgoing * energy + sheenDirect + sheenIndirect;
    }

    float3 mapped = acesFilmic(outgoing, u.camera.w);
    return float4(linearToSRGB(mapped), surfaceAlpha);
}

fragment float4 cloth_points_fragment(PointOut in [[stage_in]],
                                       float2 pc [[point_coord]],
                                       constant U &u [[buffer(0)]],
                                       texture2d<float> fillTex [[texture(0)]],
                                       sampler fillSmp [[sampler(0)]]) {
    float alpha = u.pointC.w;
    if (u.view.z > 0.5) {
        float d = length(pc - 0.5) * 2.0;
        alpha *= 1.0 - smoothstep(0.75, 1.0, d);
        if (alpha <= 0.002) discard_fragment();
    }
    float3 color = u.pointC.rgb;
    if (u.m2.y > 0.5 && u.view.w > 0.5) {
        float4 texel = fillTex.sample(fillSmp, in.uv * u.tiles.zw);
        color = mix(u.pointC.rgb, texel.rgb * u.tint.rgb, texel.a);
    }
    float3 mapped = acesFilmic(color, u.camera.w);
    return float4(linearToSRGB(mapped), alpha);
}

inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
inline float3 blendOverlay(float3 b, float3 s) {
    return select(1.0 - 2.0 * (1.0 - b) * (1.0 - s), 2.0 * b * s, b < 0.5);
}
inline float3 blendScreen(float3 b, float3 s) {
    return 1.0 - (1.0 - b) * (1.0 - s);
}

fragment float4 cloth_composite_fragment(FullOut in [[stage_in]],
                                          constant U &u [[buffer(0)]],
                                          texture2d<float> scene [[texture(0)]],
                                          sampler smp [[sampler(0)]]) {
    float2 uv = float2(in.ndc.x * 0.5 + 0.5, 0.5 - in.ndc.y * 0.5);
    float4 src = scene.sample(smp, uv);
    float overlayAmt = u.grain.x, screenAmt = u.grain.y;
    if ((overlayAmt <= 0.0 && screenAmt <= 0.0) || src.a <= 0.0) return src;

    float2 px = floor(uv * u.view.xy / max(u.grain.z, 1.0));
    float3 g1 = float3(hash21(fmod(px, 256.0)));
    float3 g2 = float3(hash21(fmod(px + float2(113.0, 71.0), 256.0) + 17.0));

    float3 c = src.rgb;
    c = mix(c, blendOverlay(c, g1), overlayAmt * src.a);
    c = mix(c, blendScreen(c, g2), screenAmt * src.a);
    return float4(c, src.a);
}
"""
}
