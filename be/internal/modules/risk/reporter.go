package risk

import (
	"context"
	"maps"
	"strings"

	"rogue-dungeon-backend/internal/modules/run"
)

type Reporter struct {
	service Service
}

func NewReporter(service Service) *Reporter {
	return &Reporter{service: service}
}

func (r *Reporter) Report(ctx context.Context, report run.RiskReport) error {
	if report.RiskScore < 30 || len(report.Reasons) == 0 {
		return nil
	}

	source := strings.TrimSpace(report.Source)
	if source == "" {
		source = "run_finish"
	}
	evidence := map[string]any{
		"source": source,
	}
	if report.Evidence != nil {
		maps.Copy(evidence, report.Evidence)
	}

	return r.service.CreateFlags(ctx, CreateFlagsInput{
		UserID:    report.UserID,
		RunID:     report.RunID,
		RiskScore: report.RiskScore,
		Reasons:   report.Reasons,
		Evidence:  evidence,
	})
}
