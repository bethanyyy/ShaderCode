Shader "Custom/Shader_Toon"
{
    Properties
    {
        [Toggle] _UseTexture("Enable Texture", Int) = 0
        _MainTex ("Texture", 2D) = "white" {}
        _TexturePower("Texture Power", Range(0, 1)) = 0.5

        [Toggle] _UseYGradient ("Height Gradient Base Color", Int) = 0
        _ColorMain ("Base Color", Color) = (1,1,1,1)
        _ColorTop ("Top Color", Color) = (1,1,1,1)
        _ColorBtm ("Bottom Color", Color) = (1,1,1,1)
        _YGradientOffset ("Height Gradient Offset", Range(0, 1)) = 0.5

        // passed in through script
        _ObjectCenter ("Object Center", Vector) = (0,0,0)
        _ObjectHeight ("Object Height", Float) = 1

        _Color2 ("Shaded Color", Color) = (1,1,1,1)
        _Ramp1FallOff("Ramp1 FallOff", Range(0, 1)) = 0.01

        // color3
        [Toggle] _UseColor3("Enable Ramp 2", Int) = 0
        _Color3 ("Shaded Color 2", Color) = (1,1,1,1)
        _Ramp2X ("Ramp2 Position", Range(-1, 0)) = -0.3
        _Ramp2FallOff("Ramp2 FallOff", Range(0, 2)) = 0.01

        // normal
        [Toggle] _UseNormalMap("Enable Normal Map", Int) = 0
        [Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalPower ("Normal Power", Range(0, 1)) = 1

        // specular
        [Toggle] _UseSpecular("Enable Specular", Int) = 0
        [HDR]_SpecularColor("Specular Color", Color) = (1,1,1,1)
        _Glossiness("Glossiness", Float) = 1

        // rim
        [Toggle] _UseRim("Enable Rim", Int) = 0
        [HDR]_RimColor("Rim Color", Color) = (1,1,1,1)
        _RimAmount("Rim Amount", Range(0, 1)) = 0
        _RimThreshold("Rim Threshold", Float) = 1
        _RimFallOff("Rim FallOff", Float) = 0.01
        [Toggle(RIM_FULL)]
        _RimFull("Show full rim", Int) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {

            Tags {
                "LightMode" = "ForwardBase"
                "PassFlags" = "OnlyDirectional"
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_fwdbase
            #pragma multi_compile _ GRADIENT_ON
            #pragma multi_compile _ RIM_ON
            #pragma multi_compile _ RAMP2_ON
            #pragma multi_compile _ NORMALMAP_ON
            #pragma multi_compile _ SPECULAR_ON
            #pragma multi_compile _ TEXTURE_ON
            #pragma shader_feature RIM_FULL

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float3 objectWorldNormal : NORMAL;
                float4 pos : SV_POSITION; // clip space position
                float3 viewDir : TEXCOORD1;

                // rotation matrix to transform from tangent to world space
                half3 tspace0 : TEXCOORD3;
                half3 tspace1 : TEXCOORD4;
                half3 tspace2 : TEXCOORD5;

                float3 worldPos : TEXCOORD6;

                SHADOW_COORDS(2)
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _TexturePower;

            sampler2D _NormalMap;
            float4 _NormalMap_ST;
            float _NormalPower;

            v2f vert (appdata v)
            {
                v2f o;

                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv = TRANSFORM_TEX(o.uv, _NormalMap);
                o.objectWorldNormal = UnityObjectToWorldNormal(v.normal);
                o.viewDir = WorldSpaceViewDir(v.vertex);

                half3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                half tangentSign = v.tangent.w * unity_WorldTransformParams.w;
                half3 worldBitangent = cross(o.objectWorldNormal, worldTangent) * tangentSign;

                // tangent space matrix
                o.tspace0 = half3(worldTangent.x, worldBitangent.x, o.objectWorldNormal.x);
                o.tspace1 = half3(worldTangent.y, worldBitangent.y, o.objectWorldNormal.y);
                o.tspace2 = half3(worldTangent.z, worldBitangent.z, o.objectWorldNormal.z);

                // from AutoLight.cginc. transform vertex from world space to shadowmap space
                TRANSFER_SHADOW(o)
                return o;
            }
            

            float4 _ColorMain;
            float4 _ColorTop;
            float4 _ColorBtm;
            float _YGradientOffset;

            float3 _ObjectCenter;
            float _ObjectHeight;

            float4 _Color2;
            float _Ramp1FallOff;

            float4 _Color3;
            float _Ramp2X;
            float _Ramp2FallOff;

            float4 _SpecularColor;
            float _Glossiness;

            float4 _RimColor;
            float _RimAmount;
            float _RimThreshold;
            float _RimFallOff;
            

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                fixed4 mainTex = tex2D(_MainTex, i.uv);
                fixed4 col = mainTex;

                // unpack normal from normal map
                half3 tangentNormal = UnpackNormal(tex2D(_NormalMap, i.uv));
                // transform normal from tangent to world space
                half3 normal;
                normal.x = dot(i.tspace0, tangentNormal);
                normal.y = dot(i.tspace1, tangentNormal);
                normal.z = dot(i.tspace2, tangentNormal);

                // original normal without using normal map
                half3 objectOrigNormal = normalize(i.objectWorldNormal);
                float3 viewDir = normalize(i.viewDir);

                // shadow
                float shadow = SHADOW_ATTENUATION(i);                

                // albedo
                #if GRADIENT_ON
                // calculate local position regardless of mesh rotation
                float3 localPos = i.worldPos.xyz - _ObjectCenter;
                float localY = localPos.y / _ObjectHeight + _YGradientOffset;
                col = lerp(_ColorBtm, _ColorTop, localY);
                #else
                col = _ColorMain;
                #endif

                #if NORMALMAP_ON
                normal = lerp(objectOrigNormal, normal, _NormalPower);
                #else
                normal = objectOrigNormal;
                #endif

                float NdotL = dot(_WorldSpaceLightPos0, normal);
                float dirLightMask1 = smoothstep(0, 0 + _Ramp1FallOff, NdotL * shadow);
                col = lerp(_Color2, col, dirLightMask1);

                #if RAMP2_ON
                float dirLightMask2 = smoothstep(_Ramp2X, _Ramp2X + _Ramp2FallOff, NdotL);
                col = lerp(_Color3, col, dirLightMask2);
                #endif

                #if TEXTURE_ON
                col = lerp(col, col * mainTex, _TexturePower);
                #endif
                
                // specular
                #if SPECULAR_ON
                float3 halfVector = normalize(_WorldSpaceLightPos0 + viewDir);
                float NdotH = dot(normal, halfVector);
                // limit specular area to lit part
                float specularValue = pow(NdotH * dirLightMask1, _Glossiness * _Glossiness);
                float specularMask = smoothstep(0.1, 0.11, specularValue);
                col = lerp(col, _SpecularColor, specularMask);
                #endif

                // takes light color into account
                col *= _LightColor0;
                
                // rim light
                #if RIM_ON
                float rimDot = dot(viewDir, normal);
                float rimValue = 0;
                #ifdef RIM_FULL
                rimValue = 1 - rimDot;
                #else
                rimValue = (1 - rimDot) * pow(NdotL * shadow, _RimThreshold);
                #endif
                float rimAmount = 1 - _RimAmount;
                float rimMask = smoothstep(rimAmount - _RimFallOff, rimAmount, rimValue);
                col += _RimColor * rimMask;
                #endif
                
                return col;
            }
            ENDCG
        }
        UsePass "Legacy Shaders/VertexLit/SHADOWCASTER"
    }
    CustomEditor "CustomShaderGUI"
}
