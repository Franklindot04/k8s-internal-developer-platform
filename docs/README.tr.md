# Kubernetes Internal Developer Platform

[English](../README.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Русский](README.ru.md) | [Türkçe](README.tr.md) | [中文](README.zh.md)

Bu depo, local-first yaklaşımına sahip bir Kubernetes İç Geliştirici Platformu (IDP) portföy projesi olarak yeniden inşa ediliyor. Amaç, yeniden üretilebilir Kubernetes ortamları, GitOps teslimatı, yeniden kullanılabilir bir Helm golden path'i, geliştirici öz hizmeti, yazılım tedarik zinciri kontrolleri, politika uygulaması, gözlemlenebilirlik, CI/CD ve operasyonel dokümantasyon aracılığıyla pratik platform mühendisliğini göstermektir.

## Mevcut Durum

Proje, temsilci fixture için Aşama 6D'deki güvenilir yayın kilometre taşını tamamladı. Aşama 1, kurtarma ve mühendislik temelini oluşturdu; Aşama 2, Kind tabanlı gerçek bir yerel küme temeli ekledi; Aşama 3, Argo CD bootstrap ve uzlaştırma kanıtını ekledi; Aşama 4, GitOps runtime doğrulamasıyla yeniden kullanılabilir bir Helm workload sözleşmesi ekledi; Aşama 5, geliştirici öz hizmeti temelini ekledi ve Aşama 6 artık korumalı `main` dalında yetkili digest aktarımıyla canlı olarak kanıtlanmış güvenilir yayına sahip.

Yerel Kubernetes temeli Kind ile uygulanmıştır. Argo CD, sabitlenmiş ve checksum ile doğrulanmış bir upstream manifestosundan kurulur ve ardından minimum platform bootstrap durumunu ve golden path demo workload'unu uzlaştırmak için kullanılır. Aşama 5, `PlatformService` depo artefaktlarını doğrulayabilir, planlayabilir, oluşturabilir ve doğrulayabilir. Aşama 6, tedarik zinciri mimarisini, temsilci build fixture'ını, güvenilmeyen PR kanıt yolunu ve herkese açık yetkili bir digest aracılığıyla güvenilir OCI yayın yolunu tanımladı. İmzalama, kriptografik provenance veya attestation, registry'ye ekli attestasyonlar, Kyverno politikaları, gözlemlenebilirlik, ortam promosyonu ve ilerideki uygulama teslimat iş akışları, sonraki aşamalar için hedef yetenekler olarak kalmaktadır.

## Hedef Yetenekler

- Kind kullanan yeniden üretilebilir yerel Kubernetes platformu
- Argo CD ile GitOps uzlaştırması
- Helm ile üretim kalitesinde yeniden kullanılabilir uygulama paketleme
- Geliştirici öz hizmeti ile servis oluşturma
- GitHub Actions doğrulama ve CI/tedarik zinciri iş akışları
- Güvenilir OCI yayını, değişmez image digest'leri, SBOM, güvenlik açığı kanıtı ve gelecekteki provenance
- Kyverno ile Kubernetes yerel politika uygulaması
- Metrikler, loglar, izleme, uyarılar ve SRE operasyonel rehberliği
- Net mimari, ADR'ler, kurtarma kayıtları ve yol haritası dokümantasyonu

## Mimari Özeti

Planlanan platform; altyapı bootstrap'ı, platform yetenekleri, referans workload'lar, geliştirici araçları ve dokümantasyonu ayırır. Yerel demonstrasyon yolu, zorunlu bulut harcaması olmadan çalıştırılabilir olacak; mimari ise gelecekteki isteğe bağlı bir bulut referans dağıtımı için alan bırakır.

Hedef mimari ve mevcut depo durumu için bkz. [docs/architecture/platform-overview.md](architecture/platform-overview.md). Aşama 6 tedarik zinciri güveni, artefaktları, kanıtları, yayını ve aktarım sözleşmeleri için bkz. [docs/supply-chain-architecture.md](supply-chain-architecture.md).

Uygulanan platform çekirdeğinden kısa bir inceleme yolu için bkz. [docs/runbooks/platform-walkthrough.md](runbooks/platform-walkthrough.md).

## Depo Yapısı

- `infra/` – küme bootstrap'ı, Argo CD control-plane bootstrap yapılandırması, gelecekteki ortam altyapısı ve platform politika bootstrap'ı.
- `platform/` – GitOps ile yönetilen platform bootstrap durumu, yeniden kullanılabilir Helm golden path chart'ı ve gelecekteki platform eklentileri ile paylaşılan sözleşmeler.
- `services/` – servis niyet kaynakları, platform tarafından yönetilen oluşturulan servis artefaktları ve gelecekteki referans workload'lar.
- `tools/` – geliştirici odaklı araçlar, servis oluşturma ve depo destek araçları.
- `docs/` – mimari, ADR'ler, kurtarma kararları, yol haritası ve gelecekteki geliştirici/operatör dokümantasyonu.
- `.github/` – depo doğrulama ve yerel platform kanıt iş akışları.
- `scripts/` – depo doğrulama, yerel Kubernetes, GitOps, Helm chart ve golden path yaşam döngüsü scriptleri.

Ayrıntılı dizin sözleşmesi [docs/repository/structure-contract.md](repository/structure-contract.md) içinde belgelenmiştir.

## Yol Haritası

Uygulama yol haritası, tamamlanmış local-first referans platform çekirdeğini ve isteğe bağlı gelecekteki genişleme alanlarını kaydeder. Politika, gözlemlenebilirlik, promosyon, provenance ve portal üzerindeki sonraki çalışmalar gelecekteki kapsamdadır ve mevcut çekirdeğin incelenmesi için bir engel teşkil etmez.

Bkz. [docs/roadmap/implementation-roadmap.md](roadmap/implementation-roadmap.md).

## Doğrulama

Depo, küçük bir statik doğrulama temeli içerir:

```bash
make help
make verify-tools
make validate
```

Doğrulama; depo yapısını, Markdown hijyenini ve dahili bağlantıları, mevcut dosyaların YAML sözdizimini, shell sözdizimini ve GitHub Actions iş akışı YAML'larını kontrol eder. Bir Kubernetes kümesi oluşturmaz, Argo CD kurmaz, workload dağıtmaz, artefakt yayınlamaz veya bulut kimlik bilgileri gerektirmez.

## Yerel Kubernetes

Aşama 2, adlandırılmış bir Kind kümesi kullanarak yeniden üretilebilir bir yerel Kubernetes temeli sağlar:

```bash
make verify-cluster-tools
make cluster-create
make cluster-status
make cluster-validate
make cluster-delete
```

Yerel platform, `idp-local` küme adını ve `kind-idp-local` kubeconfig bağlamını kullanır. Desteklenen sürümler, yaşam döngüsü davranışı, doğrulama ve sorun giderme için bkz. [docs/local-kubernetes.md](local-kubernetes.md).

## GitOps Control Plane

Aşama 3, yeniden üretilebilir bir yerel Argo CD control plane'i ve minimum Git yönetimli bootstrap kaynağı sağlar:

```bash
make gitops-install
make gitops-bootstrap
make gitops-status
make gitops-validate
make gitops-test-reconciliation
make gitops-delete
```

GitOps bootstrap, `argocd` namespace'ini kullanır, varsayılan olarak `main`'den `platform-bootstrap` Application'ını uzlaştırır ve drift düzeltmesi ile yönetilen kaynakların yeniden oluşturulmasını kanıtlar. Bkz. [docs/gitops.md](gitops.md).

## Golden Path Helm Chart

Aşama 4, sıradan HTTP servisleri için yeniden kullanılabilir bir Helm chart sağlar:

```bash
make verify-helm-tools
make helm-validate
make golden-path-bootstrap
make golden-path-status
make golden-path-validate
make golden-path-delete
```

Chart, Argo CD aracılığıyla dağıtılır, özel `golden-path` AppProject ve `golden-path-demo` Application kullanır ve digest ile sabitlenmiş imajlar, prob'lar, kaynaklar, güvenlik bağlamları, Service yönlendirmesi, ConfigMap verileri ve kesinti yönetimi dahil güvenli varsayılanları doğrular. Bkz. [docs/golden-path.md](golden-path.md).

## Katkıda Bulunma

Katkılar, `main`'e kısa ömürlü dallar ve pull request'ler kullanır. Tarihsel dallar, atıf ve kurtarma kanıtı için korunur; yeni uygulama çalışmaları için doğrudan temel olarak kullanılmamalıdır.

Bkz. [CONTRIBUTING.md](../CONTRIBUTING.md).

## Tarihsel Kurtarma

Adli denetim, tarihsel dalların yararlı tasarım kavramları içerdiği ancak toplu olarak birleştirilmemesi gerektiği sonucuna vardı. Gelecek çalışmalar, katkıda bulunanların atıflarını korurken onaylanmış kavramları kasıtlı olarak kurtaracak veya yeniden uygulayacaktır.

Bkz. [docs/recovery/historical-recovery.md](recovery/historical-recovery.md).
