import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_deal_detail_page.dart';

ExternalPartnershipModel _deal() => ExternalPartnershipModel(
  id: 'benefit',
  venueId: 'venue',
  platform: ExternalPartnershipPlatform.THE_ENTERTAINER,
  offerType: ExternalPartnershipOfferType.BOGO,
  offerLabel: 'Buy one get one free',
  status: ExternalPartnershipStatus.ACTIVE,
  createdAt: DateTime(2026),
  proofImageUrl: 'https://example.test/legacy-unmoderated-photo.jpg',
);

void main() {
  testWidgets(
    'text-only benefit keeps details and report action, not dormant image',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          // Visitor view (venue detail page).
          home: VenueDealDetailPage(
            venueName: 'Test Cafe Alpha',
            deal: _deal(),
            allowReport: true,
          ),
        ),
      );
      expect(find.text('Buy one get one free'), findsOneWidget);
      expect(find.text('Test Cafe Alpha'), findsOneWidget);
      expect(find.byTooltip('Report benefit'), findsOneWidget);
      expect(find.byType(CachedImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the venue account cannot report its own deal', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        // Venue profile opens deals without allowReport.
        home: VenueDealDetailPage(venueName: 'Test Cafe Alpha', deal: _deal()),
      ),
    );
    expect(find.text('Buy one get one free'), findsOneWidget);
    expect(find.byTooltip('Report benefit'), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsNothing);
  });
}
